extends Node3D

@export var voxel_size: float = 0.1
@export var table_height: float = 1.0

@export var shape_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(-1, 0, 0)
]

var last_grid_positions: Array[Vector3i] = []

const ROTATION_BASES = [
	# Horizontal orientations (brick lying flat)
	Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),      # 0: Along X axis
	Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD),    # 1: Along -X axis
	Basis(Vector3.BACK, Vector3.UP, Vector3.RIGHT),      # 2: Along Z axis
	Basis(Vector3.FORWARD, Vector3.UP, Vector3.LEFT),    # 3: Along -Z axis
	
	# Vertical orientations (brick standing up)
	Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT),      # 4: Vertical along Y
	Basis(Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT), # 5: Vertical along -Y
	Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD),   # 6: Vertical along Y (rotated)
	Basis(Vector3.DOWN, Vector3.LEFT, Vector3.FORWARD)   # 7: Vertical along -Y (rotated)
]

func _ready():
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

func _on_grabbed(_by):
	print("🔔 VOXEL SCRIPT: _on_grabbed() called by:", _by)
	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos)
		print("🗑️ Removed cube from position:", grid_pos)
	last_grid_positions.clear()

func _on_dropped(_by):
	print("🔹 Dropped! Old position:", get_parent().global_position)

	var obj = get_parent()
	
	# Snap rotation first
	var closest_basis = find_closest_rotation(obj.global_transform.basis)
	print("🔄 Snapped to rotation index:", ROTATION_BASES.find(closest_basis))
	
	# Get rotated offsets
	var rotated_offsets = get_rotated_offsets(closest_basis)
	
	# Find the minimum bounds (corner) of all offsets - this is our reference anchor point
	# This ensures we always snap to integer grid positions, not fractional ones
	var min_offset = get_minimum_bounds(rotated_offsets)
	print("🎯 Reference corner offset (min bounds):", min_offset)
	
	# Calculate where the reference corner is in world space from the object's current position
	var drop_pos = obj.global_position
	var reference_corner_world = drop_pos + closest_basis * (Vector3(min_offset) * voxel_size)
	
	# Snap the reference corner directly to the grid
	var snapped_reference_world = snap_to_voxel(reference_corner_world)
	var snapped_reference_grid = VoxelDatabase.world_to_grid(snapped_reference_world)
	print("🔹 Snapped reference corner at grid:", snapped_reference_grid)
	
	# Calculate where ALL voxels will be, relative to the reference corner
	# Each offset is relative to the min_offset, so we add the delta to get the final position
	var new_grid_positions: Array[Vector3i] = []
	for offset in rotated_offsets:
		var delta = offset - min_offset  # Relative to reference corner
		new_grid_positions.append(snapped_reference_grid + delta)
	
	print("🔹 Will occupy positions:", new_grid_positions)
	
	# Find all blocks that will be overlapped
	var blocks_to_delete: Array[Node] = []
	for grid_pos in new_grid_positions:
		if VoxelDatabase.has_voxel(grid_pos):
			var existing_block = VoxelDatabase.get_voxel(grid_pos)
			if existing_block != obj and is_instance_valid(existing_block):
				if existing_block not in blocks_to_delete:
					print("🗑️ Will delete overlapping block:", existing_block.name)
					blocks_to_delete.append(existing_block)
	
	# Delete overlapping blocks - remove ALL their voxels first
	for block in blocks_to_delete:
		# Get all positions this block occupies using the database helper
		var all_positions = VoxelDatabase.get_all_positions_for_object(block)
		for pos in all_positions:
			VoxelDatabase.remove_voxel(pos)
			print("  🗑️ Removed voxel at:", pos)
		
		# Now delete the node
		block.queue_free()
		print("✅ Deleted block:", block.name)
	
	# Clear old database entries for this object
	for grid_pos in last_grid_positions:
		if grid_pos not in new_grid_positions:
			VoxelDatabase.remove_voxel(grid_pos)
	
	# Calculate object center from all grid positions
	var center_world = calculate_center_from_grid_positions(new_grid_positions)
	
	# Apply final transform
	obj.global_transform = Transform3D(closest_basis, center_world)
	
	# Register in database
	for grid_pos in new_grid_positions:
		VoxelDatabase.place_voxel(grid_pos, obj)
	
	last_grid_positions = new_grid_positions
	print("✅ Registered in database at grid positions:", new_grid_positions)

	# Lock physics
	if obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
	if obj.has_method("set_sleeping"):
		obj.set_sleeping(true)

	print("✅ Object snapped and locked at:", center_world, "with rotation")

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

func find_closest_voxel_offset_to_drop_position(
	world_pos: Vector3, 
	offsets: Array[Vector3i], 
	basis: Basis
) -> Vector3i:
	var closest_offset = offsets[0]
	var min_distance = INF
	
	for offset in offsets:
		var voxel_world = world_pos + basis * (Vector3(offset) * voxel_size)
		var snapped = snap_to_voxel(voxel_world)
		var distance = world_pos.distance_to(snapped)
		
		print("  🔍 Testing offset:", offset, "-> distance:", distance)
		
		if distance < min_distance:
			min_distance = distance
			closest_offset = offset
	
	return closest_offset

func find_closest_rotation(current_basis: Basis) -> Basis:
	var best_basis = ROTATION_BASES[0]
	var best_dot = -1.0
	
	# Use the primary axis (x-axis) of the brick to determine orientation
	var current_primary = current_basis.x.normalized()
	
	for basis in ROTATION_BASES:
		var candidate_primary = basis.x.normalized()
		var dot = abs(current_primary.dot(candidate_primary))
		
		if dot > best_dot:
			best_dot = dot
			best_basis = basis
	
	return best_basis

func get_rotated_offsets(basis: Basis) -> Array[Vector3i]:
	var rotated: Array[Vector3i] = []
	
	for offset in shape_offsets:
		var rotated_vec = basis * Vector3(offset.x, offset.y, offset.z)
		rotated.append(Vector3i(
			roundi(rotated_vec.x),
			roundi(rotated_vec.y),
			roundi(rotated_vec.z)
		))
	
	return rotated

func get_minimum_bounds(offsets: Array[Vector3i]) -> Vector3i:
	# Find the minimum bounds (bottom-left-rear corner) to use as reference anchor
	# This ensures objects always snap to integer grid positions
	if offsets.is_empty():
		return Vector3i.ZERO
	
	var min_bounds = offsets[0]
	for offset in offsets:
		min_bounds.x = mini(min_bounds.x, offset.x)
		min_bounds.y = mini(min_bounds.y, offset.y)
		min_bounds.z = mini(min_bounds.z, offset.z)
	
	return min_bounds
