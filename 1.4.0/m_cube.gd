extends Node3D

@export_group("Voxel Settings")
@export var voxel_size: float = 0.1

@export_group("Shape Dimensions")
@export var use_auto_generation: bool = true
# Default to a flat panel (TV screen shape) based on your previous settings
@export var dimensions: Vector3i = Vector3i(11, 11, 1) 

@export var shape_offsets: Array[Vector3i] = [] 

# --- COOLDOWN & STATE ---
var _can_be_grabbed: bool = true
var last_grid_positions: Array[Vector3i] = []
var _all_orthogonal_bases: Array[Basis] = [] 

func _ready():
	_generate_orthogonal_bases()

	if use_auto_generation:
		_generate_procedural_offsets()

	var parent = get_parent()
	print("📐 M_CUBE: Looking for signals on:", parent)

	if parent.has_signal("dropped"):
		parent.connect("dropped", Callable(self, "_on_dropped"))
	elif parent.has_signal("released"):
		parent.connect("released", Callable(self, "_on_dropped"))
	
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))

	print("📐 M_CUBE: ✅ Ready & Connected")

func _generate_procedural_offsets():
	shape_offsets.clear()
	# Center the shape around (0,0,0)
	var start_x = -(dimensions.x - 1) / 2.0
	var start_y = -(dimensions.y - 1) / 2.0
	var start_z = -(dimensions.z - 1) / 2.0
	
	for x in range(dimensions.x):
		for y in range(dimensions.y):
			for z in range(dimensions.z):
				# Rounding to nearest int to ensure clean grid offsets
				shape_offsets.append(Vector3i(round(start_x + x), round(start_y + y), round(start_z + z)))

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

	print("📐 M_CUBE: ✊ GRABBED")
	
	var obj = get_parent()
	
	# Unlock Physics
	if obj is RigidBody3D:
		obj.freeze = false
		obj.sleeping = false
	elif obj.has_method("set_sleeping"): 
		obj.set_sleeping(false)

	# Remove old voxels
	for grid_pos in last_grid_positions:
		VoxelDatabase.remove_voxel(grid_pos, false, false)
	last_grid_positions.clear()

# ⭐ UPDATED: Added is_redo flag logic to prevent shifting
func _on_dropped(_by, is_redo: bool = false):
	# --- START COOLDOWN (0.5 seconds) ---
	_can_be_grabbed = false
	get_tree().create_timer(0.5).timeout.connect(func(): _can_be_grabbed = true)
	
	print("📐 M_CUBE: ✋ RELEASED (Calculating Snap...) Is Redo: ", is_redo)
	var obj = get_parent()
	
	var snapped_center: Vector3
	var new_grid_positions: Array[Vector3i] = []
	var closest_basis: Basis
	
	# --- 1. CALCULATE POSITIONS ---
	
	if is_redo:
		# ⭐ REDO PATH: Trust the position set by Undo System ⭐
		# Do NOT re-snap, or it will shift if not perfectly aligned with grid center logic
		snapped_center = obj.global_position
		closest_basis = obj.global_transform.basis
		
		# We still need to calculate occupied grid cells based on this position
		var rotated_offsets = get_rotated_offsets(closest_basis)
		var min_bounds = get_minimum_bounds(rotated_offsets)
		var max_bounds = get_maximum_bounds(rotated_offsets)
		var center_offset = Vector3(min_bounds + max_bounds) / 2.0
		
		for offset in rotated_offsets:
			var relative_to_center = Vector3(offset) - center_offset
			var world_pos = snapped_center + relative_to_center * voxel_size
			var grid_pos = VoxelDatabase.world_to_grid(world_pos)
			new_grid_positions.append(grid_pos)
			
	else:
		# ⭐ NORMAL DROP PATH: Calculate Snap ⭐
		closest_basis = find_closest_rotation(obj.global_transform.basis)
		
		var rotated_offsets = get_rotated_offsets(closest_basis)
		var min_bounds = get_minimum_bounds(rotated_offsets)
		var max_bounds = get_maximum_bounds(rotated_offsets)
		var current_dims = max_bounds - min_bounds + Vector3i.ONE
		var center_offset = Vector3(min_bounds + max_bounds) / 2.0
		
		# Snap the CENTER
		var drop_pos = obj.global_position
		snapped_center = snap_center_for_dimensions(drop_pos, current_dims)
		
		# Calculate new grid positions
		for offset in rotated_offsets:
			var relative_to_center = Vector3(offset) - center_offset
			var world_pos = snapped_center + relative_to_center * voxel_size
			var grid_pos = VoxelDatabase.world_to_grid(world_pos)
			new_grid_positions.append(grid_pos)

	print("📐 M_CUBE: ✅ New Grid Positions Size: ", new_grid_positions.size())
	
	# --- 2. CLEAR OVERLAPS ---
	
	# Force cleanup of zombie nodes to prevent "Space Occupied" errors
	var overlap_found := false
	for grid_pos in new_grid_positions:
		if VoxelDatabase.has_voxel(grid_pos):
			var existing_block := VoxelDatabase.get_voxel(grid_pos)
			if existing_block != obj and is_instance_valid(existing_block):
				overlap_found = true
				break

	if overlap_found:
		print("📐 M_CUBE: ❌ Placement blocked – space already occupied. Deleting M_CUBE.")
		obj.queue_free()
		return

	# Clean up leftovers from previous position (old cells not in the new footprint)
	for grid_pos in last_grid_positions:
		if grid_pos not in new_grid_positions:
			VoxelDatabase.remove_voxel(grid_pos, false, false)
	
	# --- 3. APPLY TRANSFORM ---
	# Only apply transform if NOT Redo (Redo sets it externally)
	if not is_redo:
		obj.global_transform = Transform3D(closest_basis, snapped_center)
	
	# --- 4. REGISTER IN DATABASE ---
	var mesh = obj.get_node_or_null("MeshInstance3D")
	var current_color = Color.WHITE
	if mesh and mesh.has_method("get_color"):
		current_color = mesh.get_color()
	
	var shape_type = obj.get_meta("shape_type", "m_cube")
	
	if not is_redo:
		VoxelDatabase.start_batch() 

	for i in range(new_grid_positions.size()):
		var grid_pos = new_grid_positions[i]
		var is_master_block = (i == 0) # Index 0 is Master
		
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type, current_color, is_redo, is_master_block)
	
	if not is_redo:
		VoxelDatabase.end_batch("place")
	
	last_grid_positions = new_grid_positions

	# --- 5. LOCK PHYSICS ---
	if obj is RigidBody3D:
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
		obj.freeze = true
	elif obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
		if obj.has_method("set_sleeping"):
			obj.set_sleeping(true)
		
	print("📐 M_CUBE: 🔒 SNAPPED & LOCKED at ", snapped_center)

# --- HELPER FUNCTIONS ---

func snap_center_for_dimensions(center: Vector3, dimensions: Vector3i) -> Vector3:
	var snapped = Vector3.ZERO
	for i in range(3):
		if dimensions[i] % 2 == 0:
			# EVEN dimension
			snapped[i] = (floorf(center[i] / voxel_size) + 0.5) * voxel_size
		else:
			# ODD dimension
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
