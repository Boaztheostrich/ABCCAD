extends Node3D

@export var voxel_size: float = 0.1
@export var table_height: float = 1.0

var last_grid_pos: Vector3i  # Track where this cube was last placed

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
	
	# Connect to grabbed signal to remove from database when picked up
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))
		print("✅ Connected to grabbed!")

func _on_grabbed(_by):
	print("🔔🔔🔔 VOXEL SCRIPT: _on_grabbed() was called!")
	print("🔔🔔🔔 Called by:", _by)
	# Remove this cube from its last known position in the database
	if last_grid_pos != Vector3i.ZERO or VoxelDatabase.has_voxel(last_grid_pos):
		VoxelDatabase.remove_voxel(last_grid_pos)
		print("🗑️ Removed cube from old position:", last_grid_pos)

func _on_dropped(_by):
	print("🔹 Dropped! Old position:", get_parent().global_position)

	var obj = get_parent()
	var snapped_pos = snap_to_voxel(obj.global_position)
	print("🔹 Snapped to:", snapped_pos)

	# Calculate the new grid position
	var grid_pos = VoxelDatabase.world_to_grid(snapped_pos)
	
	# 🆕 CHECK FOR OVERLAP: If another block exists at this position, remove it
	if VoxelDatabase.has_voxel(grid_pos):
		var existing_block = VoxelDatabase.get_voxel(grid_pos)
		
		# Make sure it's not the same block (edge case)
		if existing_block != obj and is_instance_valid(existing_block):
			print("⚠️ Block collision detected at", grid_pos)
			print("   Removing existing block:", existing_block.name)
			
			# Remove from database first
			VoxelDatabase.remove_voxel(grid_pos)
			
			# Delete the physical block from the scene
			existing_block.queue_free()
			print("✅ Old block removed from scene and database")

	# Update transform to snapped position
	obj.global_transform = Transform3D(Basis(), snapped_pos)

	# Remove this block from its old position (if it had one)
	if last_grid_pos != Vector3i.ZERO and last_grid_pos != grid_pos:
		VoxelDatabase.remove_voxel(last_grid_pos)
	
	# Register in the database at new position
	VoxelDatabase.place_voxel(grid_pos, obj)
	last_grid_pos = grid_pos
	print("✅ Registered in database at grid position:", grid_pos)

	# Lock rotation & reset velocities
	if obj.has_method("set_linear_velocity"):
		obj.set_linear_velocity(Vector3.ZERO)
		obj.set_angular_velocity(Vector3.ZERO)
	if obj.has_method("set_sleeping"):
		obj.set_sleeping(true)

	print("✅ Object snapped and locked at:", snapped_pos)

func snap_to_voxel(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / voxel_size) * voxel_size,
		round(pos.y / voxel_size) * voxel_size,
		round(pos.z / voxel_size) * voxel_size
	)
