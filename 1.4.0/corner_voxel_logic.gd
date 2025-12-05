extends Node3D

@export var voxel_size: float = 0.1
@export var table_height: float = 1.0

@export var shape_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0)
]

var last_grid_positions: Array[Vector3i] = []
var _all_orthogonal_bases: Array[Basis] = []

func _ready():
	_generate_orthogonal_bases()
	
	var parent = get_parent()
	print("Looking for signals on:", parent)
	
	if parent.has_signal("dropped"):
		parent.connect("dropped", Callable(self, "_on_dropped"))
		print("✅ Connected to dropped!")
	elif parent.has_signal("released"):
		parent.connect("released", Callable(self, "_on_dropped"))
		print("✅ Connected to released!")
	else:
		print("❌ Couldn't find a 'drop' signal")
	
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))
		print("✅ Connected to grabbed!")
	
	_print_debug_info("🟢 SPAWNED")

func _generate_orthogonal_bases():
	_all_orthogonal_bases.clear()
	var dirs = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	
	for forward in dirs:
		for up in dirs:
			if abs(forward.dot(up)) > 0.9:
				continue
			var right = forward.cross(up).normalized()
			_all_orthogonal_bases.append(Basis(right, up, -forward))
	
	print("✅ Generated ", _all_orthogonal_bases.size(), " orthogonal bases")

func find_closest_rotation(current_basis: Basis) -> Basis:
	var best_basis = Basis.IDENTITY
	var max_score = -INF
	var clean_current = current_basis.orthonormalized()
	
	var best_index = -1
	
	print("   --- find_closest_rotation() ---")
	print("   Input basis (orthonormalized):")
	print("      X (Right):   ", clean_current.x)
	print("      Y (Up):      ", clean_current.y)
	print("      Z (Forward): ", clean_current.z)
	
	var top_candidates: Array = []  # Track top 3 for debugging

	for i in range(_all_orthogonal_bases.size()):
		var candidate = _all_orthogonal_bases[i]
		var score = (
			clean_current.x.dot(candidate.x) + 
			clean_current.y.dot(candidate.y) + 
			clean_current.z.dot(candidate.z)
		)
		
		top_candidates.append({"index": i, "score": score, "basis": candidate})
		
		if score > max_score:
			max_score = score
			best_basis = candidate
			best_index = i
	
	# Sort and show top 3 candidates
	top_candidates.sort_custom(func(a, b): return a["score"] > b["score"])
	print("   Top 3 candidates:")
	for j in range(mini(3, top_candidates.size())):
		var c = top_candidates[j]
		print("      [", c["index"], "] Score: ", snapped(c["score"], 0.001))
		print("         X:", c["basis"].x, " Y:", c["basis"].y, " Z:", c["basis"].z)
	
	print("   ✅ Selected basis index: ", best_index, " with score: ", snapped(max_score, 0.001))
	print("   --- end ---")
	
	return best_basis

func _on_grabbed(_by):
	_print_debug_info("✊ GRABBED")
	
	var obj = get_parent()
	if obj.has_method("set_sleeping"): obj.set_sleeping(false)
	if obj is RigidBody3D: obj.freeze = false

	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos)
	last_grid_positions.clear()

func _on_dropped(_by):
	_print_debug_info("✋ RELEASED (Before Snap)")
	var obj = get_parent()
	
	print("   📦 Original shape_offsets: ", shape_offsets)
	
	# 1. Find Closest Rotation
	var closest_basis = find_closest_rotation(obj.global_transform.basis)
	print("   🔄 SELECTED Closest basis:")
	print("      X (Right):   ", closest_basis.x)
	print("      Y (Up):      ", closest_basis.y)
	print("      Z (Forward): ", closest_basis.z)
	
	# 2. Get Rotated Offsets and calculate dimensions
	var rotated_offsets = get_rotated_offsets(closest_basis)
	print("   🔄 Rotated offsets: ", rotated_offsets)
	
	var min_bounds = get_minimum_bounds(rotated_offsets)
	var max_bounds = get_maximum_bounds(rotated_offsets)
	var dimensions = max_bounds - min_bounds + Vector3i.ONE
	print("   📐 Bounds - Min: ", min_bounds, " Max: ", max_bounds, " Dimensions: ", dimensions)
	
	# 3. Calculate the geometric center offset (in grid units)
	var center_offset = Vector3(min_bounds + max_bounds) / 2.0
	print("   🎯 Center offset (grid units): ", center_offset)
	
	# 4. Snap the CENTER directly based on even/odd dimensions
	var drop_pos = obj.global_position
	var snapped_center = snap_center_for_dimensions(drop_pos, dimensions)
	print("   📍 Drop position: ", drop_pos)
	print("   📍 Snapped center: ", snapped_center)
	
	# 5. Calculate grid positions from the snapped center
	var new_grid_positions: Array[Vector3i] = []
	for offset in rotated_offsets:
		var relative_to_center = Vector3(offset) - center_offset
		var world_pos = snapped_center + relative_to_center * voxel_size
		var grid_pos = VoxelDatabase.world_to_grid(world_pos)
		print("   🧱 Offset: ", offset, " -> relative: ", relative_to_center, " -> grid: ", grid_pos)
		new_grid_positions.append(grid_pos)
	
	print("   ✅ Final grid positions: ", new_grid_positions)
	
	# 6. Clear Overlaps
	var blocks_to_delete: Array[Node] = []
	for grid_pos in new_grid_positions:
		if VoxelDatabase.has_voxel(grid_pos):
			var existing_block = VoxelDatabase.get_voxel(grid_pos)
			if existing_block != obj and is_instance_valid(existing_block):
				if existing_block not in blocks_to_delete:
					blocks_to_delete.append(existing_block)
	
	for block in blocks_to_delete:
		for pos in VoxelDatabase.get_all_positions_for_object(block):
			VoxelDatabase.remove_voxel(pos)
		block.queue_free()

	for grid_pos in last_grid_positions:
		if grid_pos not in new_grid_positions:
			VoxelDatabase.remove_voxel(grid_pos)
	
	# 7. Apply Transform
	obj.global_transform = Transform3D(closest_basis, snapped_center)
	print("   🎯 Final center: ", snapped_center)
	
	# 8. Register
	var mesh = obj.get_node_or_null("MeshInstance3D")
	var current_color = Color.WHITE
	if mesh and mesh.has_method("get_color"):
		current_color = mesh.get_color()
	
	var shape_type = obj.get_meta("shape_type", "corner_piece")
	for grid_pos in new_grid_positions:
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type, current_color)
	
	last_grid_positions = new_grid_positions

	# Lock Physics
	if obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
	if obj.has_method("set_sleeping"):
		obj.set_sleeping(true)
		
	_print_debug_info("🔒 SNAPPED & LOCKED")

func snap_center_for_dimensions(center: Vector3, dimensions: Vector3i) -> Vector3:
	var snapped = Vector3.ZERO
	
	for i in range(3):
		if dimensions[i] % 2 == 0:
			# EVEN dimension: center at half-voxel positions
			snapped[i] = (floorf(center[i] / voxel_size) + 0.5) * voxel_size
		else:
			# ODD dimension: center at whole-voxel positions
			snapped[i] = roundf(center[i] / voxel_size) * voxel_size
	
	print("   📐 snap_center_for_dimensions:")
	print("      Input: ", center)
	print("      Dimensions: ", dimensions)
	print("      Even/Odd: [", "even" if dimensions.x % 2 == 0 else "odd", ", ", 
							  "even" if dimensions.y % 2 == 0 else "odd", ", ",
							  "even" if dimensions.z % 2 == 0 else "odd", "]")
	print("      Output: ", snapped)
	
	return snapped

func get_rotated_offsets(basis: Basis) -> Array[Vector3i]:
	var rotated: Array[Vector3i] = []
	for offset in shape_offsets:
		var rotated_vec = basis * Vector3(offset.x, offset.y, offset.z)
		rotated.append(Vector3i(roundi(rotated_vec.x), roundi(rotated_vec.y), roundi(rotated_vec.z)))
	return rotated

func get_minimum_bounds(offsets: Array[Vector3i]) -> Vector3i:
	if offsets.is_empty(): return Vector3i.ZERO
	var min_bounds = offsets[0]
	for offset in offsets:
		min_bounds.x = mini(min_bounds.x, offset.x)
		min_bounds.y = mini(min_bounds.y, offset.y)
		min_bounds.z = mini(min_bounds.z, offset.z)
	return min_bounds

func get_maximum_bounds(offsets: Array[Vector3i]) -> Vector3i:
	if offsets.is_empty(): return Vector3i.ZERO
	var max_bounds = offsets[0]
	for offset in offsets:
		max_bounds.x = maxi(max_bounds.x, offset.x)
		max_bounds.y = maxi(max_bounds.y, offset.y)
		max_bounds.z = maxi(max_bounds.z, offset.z)
	return max_bounds

func _print_debug_info(stage: String):
	var obj = get_parent()
	var basis = obj.global_transform.basis
	var euler = basis.get_euler()
	print("========================================")
	print("🔺 [WEDGE DEBUG]: ", stage)
	print("   Block Name: ", obj.name)
	print("   Global Position: ", obj.global_position)
	print("   --- ORIENTATION (Current) ---")
	print("   X (Right):   ", basis.x)
	print("   Y (Up):      ", basis.y)
	print("   Z (Forward): ", basis.z)
	print("   Rotation (Deg): ", Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)))
	print("   --- SHAPE ---")
	print("   shape_offsets: ", shape_offsets)
	print("   last_grid_positions: ", last_grid_positions)
	print("========================================")
