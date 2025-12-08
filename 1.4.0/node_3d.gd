extends Node3D

@export var voxel_size: float = 0.1
@export var table_height: float = 1.0

# --- CUBE DEFINITION (Just one block at 0,0,0) ---
@export var shape_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0)
]

# --- COOLDOWN (Prevents the jumpy physics loop) ---
var _can_be_grabbed: bool = true

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
	
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))
		print("✅ Connected to grabbed!")

func _generate_orthogonal_bases():
	_all_orthogonal_bases.clear()
	var dirs = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for forward in dirs:
		for up in dirs:
			if abs(forward.dot(up)) > 0.9: continue
			var right = forward.cross(up).normalized()
			_all_orthogonal_bases.append(Basis(right, up, -forward))

func find_closest_rotation(current_basis: Basis) -> Basis:
	var best_basis = Basis.IDENTITY
	var max_score = -INF
	var clean_current = current_basis.orthonormalized()

	for candidate in _all_orthogonal_bases:
		var score = (clean_current.x.dot(candidate.x) + 
					 clean_current.y.dot(candidate.y) + 
					 clean_current.z.dot(candidate.z))
		if score > max_score:
			max_score = score
			best_basis = candidate
	
	return best_basis

func _on_grabbed(_pickable, _by):
	# --- COOLDOWN CHECK ---
	if not _can_be_grabbed:
		return
	
	print("🔔 VOXEL SCRIPT: _on_grabbed()")
	
	var obj = get_parent()
	if obj.has_method("set_sleeping"): obj.set_sleeping(false)
	if obj is RigidBody3D: obj.freeze = false

	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos, false, false)
	last_grid_positions.clear()

func _on_dropped(_by, _is_redo: bool = false):
	# --- START COOLDOWN (0.5 seconds) ---
	_can_be_grabbed = false
	get_tree().create_timer(0.5).timeout.connect(func(): _can_be_grabbed = true)
	
	print("✋ RELEASED (Before Snap)")
	var obj = get_parent()
	
	# 1. Find Closest Rotation
	var closest_basis = find_closest_rotation(obj.global_transform.basis)
	
	# 2. Get Rotated Offsets and calculate dimensions
	var rotated_offsets = get_rotated_offsets(closest_basis)
	
	var min_bounds = get_minimum_bounds(rotated_offsets)
	var max_bounds = get_maximum_bounds(rotated_offsets)
	# For a single cube, dimensions will always be (1,1,1)
	var dimensions = max_bounds - min_bounds + Vector3i.ONE
	
	# 3. Calculate the geometric center offset
	var center_offset = Vector3(min_bounds + max_bounds) / 2.0
	
	# 4. Snap the CENTER (The logic you liked from the Brick script)
	var drop_pos = obj.global_position
	var snapped_center = snap_center_for_dimensions(drop_pos, dimensions)
	
	# 5. Calculate grid positions
	var new_grid_positions: Array[Vector3i] = []
	for offset in rotated_offsets:
		var relative_to_center = Vector3(offset) - center_offset
		var world_pos = snapped_center + relative_to_center * voxel_size
		var grid_pos = VoxelDatabase.world_to_grid(world_pos)
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
			VoxelDatabase.remove_voxel(pos, false, false)
		block.queue_free()

	for grid_pos in last_grid_positions:
		if grid_pos not in new_grid_positions:
			VoxelDatabase.remove_voxel(grid_pos, false, false)
	
	# 7. Apply Transform
	obj.global_transform = Transform3D(closest_basis, snapped_center)
	
	# 8. Register
	var mesh = obj.get_node_or_null("MeshInstance3D")
	var current_color = Color.WHITE
	if mesh and mesh.has_method("get_color"):
		current_color = mesh.get_color()
	
	var shape_type = obj.get_meta("shape_type", "cube")
	for grid_pos in new_grid_positions:
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type, current_color)
	
	last_grid_positions = new_grid_positions

	# Lock Physics
	if obj is RigidBody3D:
		obj.freeze = true
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
	elif obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
		if obj.has_method("set_sleeping"):
			obj.set_sleeping(true)
		
	print("🔒 SNAPPED & LOCKED at ", snapped_center)

# --- THE MAGIC FUNCTION ---
# This decides if we snap to 0.0, 1.0, 2.0 (Odd size) OR 0.5, 1.5, 2.5 (Even size)
func snap_center_for_dimensions(center: Vector3, dimensions: Vector3i) -> Vector3:
	var snapped = Vector3.ZERO
	
	for i in range(3):
		if dimensions[i] % 2 == 0:
			# EVEN dimension (2, 4, 6...): Snap to half-voxel positions
			snapped[i] = (floorf(center[i] / voxel_size) + 0.5) * voxel_size
		else:
			# ODD dimension (1, 3, 5...): Snap to whole-voxel positions
			snapped[i] = roundf(center[i] / voxel_size) * voxel_size
	
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
