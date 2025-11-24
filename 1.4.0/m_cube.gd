extends Node3D

@export_group("Voxel Settings")
@export var voxel_size: float = 0.1

@export_group("Shape Dimensions")
@export var use_auto_generation: bool = true
# SWAPPED X and Z based on your previous logs to make it a "TV Screen" default
@export var dimensions: Vector3i = Vector3i(11, 11, 1) 

@export var shape_offsets: Array[Vector3i] = [] 

var last_grid_positions: Array[Vector3i] = []
var _all_orthogonal_bases: Array[Basis] = [] 

func _ready():
	_generate_orthogonal_bases()

	if use_auto_generation:
		_generate_procedural_offsets()

	var parent = get_parent()
	if parent.has_signal("dropped"):
		parent.connect("dropped", Callable(self, "_on_dropped"))
	elif parent.has_signal("released"):
		parent.connect("released", Callable(self, "_on_dropped"))
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))

	_print_debug_info("🟢 SPAWNED")

func _generate_procedural_offsets():
	shape_offsets.clear()
	var start_x = -(dimensions.x - 1) / 2.0
	var start_y = -(dimensions.y - 1) / 2.0
	var start_z = -(dimensions.z - 1) / 2.0
	
	for x in range(dimensions.x):
		for y in range(dimensions.y):
			for z in range(dimensions.z):
				shape_offsets.append(Vector3i(start_x + x, start_y + y, start_z + z))

# --- THE FIX IS HERE ---
func _generate_orthogonal_bases():
	_all_orthogonal_bases.clear()
	var dirs = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for forward in dirs:
		for up in dirs:
			if abs(forward.dot(up)) > 0.9: continue
			
			# FIX: Changed order from up.cross(forward) to forward.cross(up)
			# This ensures we generate Right-Handed bases (Standard Rotations)
			# instead of Mirrored bases (Reflections).
			var right = forward.cross(up).normalized()
			
			_all_orthogonal_bases.append(Basis(right, up, -forward))

func find_closest_rotation(current_basis: Basis) -> Basis:
	var best_basis = Basis.IDENTITY
	var max_score = -INF
	var clean_current = current_basis.orthonormalized()

	for candidate in _all_orthogonal_bases:
		# Compare alignment of all 3 axes
		var score = (clean_current.x.dot(candidate.x) + 
					 clean_current.y.dot(candidate.y) + 
					 clean_current.z.dot(candidate.z))
		if score > max_score:
			max_score = score
			best_basis = candidate
	
	return best_basis

# --- STANDARD LOGIC ---

func _on_grabbed(_by):
	_print_debug_info("✊ GRABBED")
	
	# Wake up physics so it feels natural in hand
	var obj = get_parent()
	if obj.has_method("set_sleeping"): obj.set_sleeping(false)
	if obj is RigidBody3D: obj.freeze = false

	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos)
	last_grid_positions.clear()

func _on_dropped(_by):
	_print_debug_info("✋ RELEASED (Before Snap)")
	var obj = get_parent()
	
	# 1. Find Closest Rotation
	var closest_basis = find_closest_rotation(obj.global_transform.basis)
	
	# 2. Get Offsets (These are already rotated relative to center!)
	var rotated_offsets = get_rotated_offsets(closest_basis)
	var min_offset = get_minimum_bounds(rotated_offsets)
	
	# 3. Calculate Anchors
	var drop_pos = obj.global_position
	
	# FIX: Do NOT multiply by basis here. min_offset is already rotated in Step 2.
	var pivot_to_corner = Vector3(min_offset) * voxel_size
	
	var corner_world_pos = drop_pos + pivot_to_corner
	var snapped_corner = snap_to_voxel(corner_world_pos)
	var snapped_grid_start = VoxelDatabase.world_to_grid(snapped_corner)
	
	# 4. Generate New Grid Positions
	var new_grid_positions: Array[Vector3i] = []
	for offset in rotated_offsets:
		# offset - min_offset gives us index relative to the corner (0,0,0), (1,0,0)...
		var local_pos = offset - min_offset
		new_grid_positions.append(snapped_grid_start + local_pos)
	
	# 5. Clear Overlaps
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
	
	# 6. Apply Transform
	var center_world = calculate_center_from_grid_positions(new_grid_positions)
	obj.global_transform = Transform3D(closest_basis, center_world)
	
	# 7. Register
	var shape_type = obj.get_meta("shape_type", "cube")
	for grid_pos in new_grid_positions:
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type)
	
	last_grid_positions = new_grid_positions

	# Lock Physics
	if obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
	if obj.has_method("set_sleeping"):
		obj.set_sleeping(true)
		
	_print_debug_info("🔒 SNAPPED & LOCKED")

func calculate_center_from_grid_positions(grid_positions: Array[Vector3i]) -> Vector3:
	var sum = Vector3.ZERO
	for grid_pos in grid_positions:
		sum += VoxelDatabase.grid_to_world(grid_pos)
	return sum / grid_positions.size()

func snap_to_voxel(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / voxel_size) * voxel_size,
		round(pos.y / voxel_size) * voxel_size,
		round(pos.z / voxel_size) * voxel_size
	)

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

func _print_debug_info(stage: String):
	var obj = get_parent()
	var basis = obj.global_transform.basis
	var euler = basis.get_euler()
	print("========================================")
	print("📐 [DEBUG STATE]: ", stage)
	print("   Block Name: ", obj.name)
	print("   Global Position: ", obj.global_position)
	print("   --- ORIENTATION ---")
	print("   Forward (Z): ", basis.z)
	print("   Up (Y):      ", basis.y)
	print("   Right (X):   ", basis.x)
	print("   Rotation (Deg): ", Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)))
	print("========================================")
