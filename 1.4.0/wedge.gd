extends Node3D

@export var voxel_size: float = 0.1
@export var table_height: float = 1.0

@export var shape_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0)
]

var last_grid_positions: Array[Vector3i] = []

# --- REPLACE YOUR EXISTING ROTATION LOGIC WITH THIS ---

# We don't hardcode the list anymore; we generate the 24 valid orthogonal rotations
var _all_orthogonal_bases: Array[Basis] = []

func _generate_orthogonal_bases():
	# Define the 6 cardinal directions
	var dirs = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	
	for forward in dirs:
		for up in dirs:
			# Skip if forward and up are parallel (can't form a basis)
			if abs(forward.dot(up)) > 0.9:
				continue
				
			# Create a valid 90-degree rotation basis
			var right = up.cross(forward).normalized()
			var valid_basis = Basis(right, up, -forward) # Godot uses -Z as forward
			_all_orthogonal_bases.append(valid_basis)

func find_closest_rotation(current_basis: Basis) -> Basis:
	var best_basis = Basis.IDENTITY
	var max_score = -INF

	# We orthonormalize the input just in case physics jitter skewed it
	var clean_current = current_basis.orthonormalized()

	for candidate in _all_orthogonal_bases:
		# Calculate a "similarity score" by comparing all 3 axes (X, Y, and Z)
		# Dot product of 1.0 means perfectly aligned. 
		# Max score is 3.0 (X matches X, Y matches Y, Z matches Z)
		var score = (
			clean_current.x.dot(candidate.x) + 
			clean_current.y.dot(candidate.y) + 
			clean_current.z.dot(candidate.z)
		)
		
		if score > max_score:
			max_score = score
			best_basis = candidate
			
	return best_basis

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
	print("🔄 Snapped to rotation index:", _all_orthogonal_bases.find(closest_basis))
	
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
	# Register in database
	for grid_pos in new_grid_positions:
		var shape_type = obj.get_meta("shape_type", "cube")  # Changed from self to obj
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type)  # Changed from self to obj
	
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
