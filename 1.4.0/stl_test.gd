extends Node3D

func _ready():
	print("🚀 Testing VoxelDatabase...")
	
	# Test 1: Place some voxels in the database
	var test_positions = [
		Vector3(0, 0, 0),
		Vector3(0.1, 0, 0),
		Vector3(0.2, 0, 0)
	]
	
	for pos in test_positions:
		var grid_pos = VoxelDatabase.world_to_grid(pos)
		VoxelDatabase.place_voxel(grid_pos, self)  # using self as placeholder
	
	# Test 2: Query the database
	print("📊 Total voxels in database:", VoxelDatabase.get_voxel_count())
	print("📋 All grid positions:", VoxelDatabase.get_all_voxels())
	
	# Test 3: Check if specific position exists
	var check_pos = VoxelDatabase.world_to_grid(Vector3(0.1, 0, 0))
	print("❓ Has voxel at", check_pos, "?", VoxelDatabase.has_voxel(check_pos))
	
	# Test 4: Remove a voxel
	VoxelDatabase.remove_voxel(check_pos)
	print("📊 After removal, total voxels:", VoxelDatabase.get_voxel_count())
	
	print("✅ VoxelDatabase tests complete!")
