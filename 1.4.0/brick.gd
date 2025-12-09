extends Node3D

@export var voxel_size: float = 0.1

# --- BRICK DEFINITION (2x1 Block) ---
# This is the only part that differs structurally from the Cube script
@export var shape_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(-1, 0, 0)
]

# --- COOLDOWN (Prevents the jumpy physics loop) ---
var _can_be_grabbed: bool = true

var last_grid_positions: Array[Vector3i] = []
var _all_orthogonal_bases: Array[Basis] = []

func _ready():
	_generate_orthogonal_bases()
	
	var parent = get_parent()
	print("🧱 BRICK: Looking for signals on:", parent)
	
	if parent.has_signal("dropped"):
		parent.connect("dropped", Callable(self, "_on_dropped"))
	elif parent.has_signal("released"):
		parent.connect("released", Callable(self, "_on_dropped"))
	
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))
	
	print("🧱 BRICK: ✅ Ready & Connected")

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

# Updated to accept 2 arguments to match your XR system
func _on_grabbed(_pickable, _by):
	# --- COOLDOWN CHECK ---
	if not _can_be_grabbed:
		return
	
	print("🧱 BRICK: ✊ GRABBED")
	
	var obj = get_parent()
	
	# Unlock Physics
	if obj is RigidBody3D:
		obj.freeze = false
		obj.sleeping = false
	elif obj.has_method("set_sleeping"): 
		obj.set_sleeping(false)

	# Remove old voxels efficiently
	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos, false, false)
	last_grid_positions.clear()

func _on_dropped(_by, is_redo: bool = false):
	# --- START COOLDOWN (0.5 seconds) ---
	_can_be_grabbed = false
	get_tree().create_timer(0.5).timeout.connect(func(): _can_be_grabbed = true)
	
	print("🧱 BRICK: ✋ RELEASED (Calculating Snap...)")
	var obj = get_parent()
	
	# 1. Find Closest Rotation
	var closest_basis = find_closest_rotation(obj.global_transform.basis)
	
	# 2. Get Rotated Offsets
	var rotated_offsets = get_rotated_offsets(closest_basis)
	
	# 3. Calculate Dimensions (This changes based on rotation for a brick!)
	var min_bounds = get_minimum_bounds(rotated_offsets)
	var max_bounds = get_maximum_bounds(rotated_offsets)
	var dimensions = max_bounds - min_bounds + Vector3i.ONE
	
	# 4. Calculate geometric center offset
	var center_offset = Vector3(min_bounds + max_bounds) / 2.0
	
	# 5. Snap the CENTER (Handles Even vs Odd dimensions)
	var drop_pos = obj.global_position
	var snapped_center = snap_center_for_dimensions(drop_pos, dimensions)
	
	# 6. Calculate new grid positions
	var new_grid_positions: Array[Vector3i] = []
	for offset in rotated_offsets:
		var relative_to_center = Vector3(offset) - center_offset
		var world_pos = snapped_center + relative_to_center * voxel_size
		var grid_pos = VoxelDatabase.world_to_grid(world_pos)
		new_grid_positions.append(grid_pos)
	
	print("🧱 BRICK: ✅ New Grid Positions: ", new_grid_positions)
	
	# 7. Clear Overlaps (Prevents Z-Fighting)
# 7. CHECK FOR OVERLAP BEFORE PLACING
	var overlap_found := false

	for grid_pos in new_grid_positions:
		# If ANY grid cell is already occupied by a *different* object, we block placement
		if VoxelDatabase.has_voxel(grid_pos):
			var existing_block := VoxelDatabase.get_voxel(grid_pos)
			if existing_block != obj and is_instance_valid(existing_block):
				overlap_found = true
				break

	if overlap_found:
		print("🧱 BRICK: ❌ Placement blocked – space already occupied. Deleting brick.")
		# Option A: simply delete this brick instance
		obj.queue_free()
		return

	# Clean up any leftover positions from previous state
	for grid_pos in last_grid_positions:
		if grid_pos not in new_grid_positions:
			VoxelDatabase.remove_voxel(grid_pos, false, false)
	
	# 8. Apply Transform
	obj.global_transform = Transform3D(closest_basis, snapped_center)
	
	# 9. Register in Database
	var mesh = obj.get_node_or_null("MeshInstance3D")
	var current_color = Color.WHITE
	if mesh and mesh.has_method("get_color"):
		current_color = mesh.get_color()
	
	var shape_type = obj.get_meta("shape_type", "brick")

	# CHANGE 2: Only start a batch if this is a NEW action (not a Redo)
	if not is_redo:
		VoxelDatabase.start_batch() 

	# CHANGE 3: The Master/Follower Loop
	for i in range(new_grid_positions.size()):
		var grid_pos = new_grid_positions[i]
		
		# The first block in the list is the "Master"
		var is_master_block = (i == 0)
		
		# place_voxel(pos, obj, type, color, IS_UNDO_REDO, IS_MASTER)
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type, current_color, is_redo, is_master_block)
	
	# CHANGE 4: Only end batch if this was a NEW action
	if not is_redo:
		VoxelDatabase.end_batch("place")
	
	last_grid_positions = new_grid_positions

	# 10. Lock Physics
	if obj is RigidBody3D:
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
		obj.freeze = true
	elif obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
		if obj.has_method("set_sleeping"):
			obj.set_sleeping(true)
		
	print("🧱 BRICK: 🔒 SNAPPED & LOCKED at ", snapped_center)

# --- THE MAGIC FUNCTION ---
# Handles the difference between snapping a 1x1 (Odd) vs a 2x1 (Even) block
func snap_center_for_dimensions(center: Vector3, dimensions: Vector3i) -> Vector3:
	var snapped = Vector3.ZERO
	
	for i in range(3):
		if dimensions[i] % 2 == 0:
			# EVEN dimension (2, 4...): Snap to half-voxel (0.05, 0.15)
			snapped[i] = (floorf(center[i] / voxel_size) + 0.5) * voxel_size
		else:
			# ODD dimension (1, 3...): Snap to whole-voxel (0.0, 0.1)
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
