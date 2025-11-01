# VoxelDatabase.gd
extends Node

# Dictionary with Vector3i keys (grid positions) and object references as values
var voxel_grid: Dictionary = {}
var voxel_size: float = 0.1

signal voxel_placed(grid_pos: Vector3i, object: Node3D)
signal voxel_removed(grid_pos: Vector3i)

func world_to_grid(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		roundi(world_pos.x / voxel_size),
		roundi(world_pos.y / voxel_size),
		roundi(world_pos.z / voxel_size)
	)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	return Vector3(
		grid_pos.x * voxel_size,
		grid_pos.y * voxel_size,
		grid_pos.z * voxel_size
	)

func place_voxel(grid_pos: Vector3i, obj: Node3D):
	voxel_grid[grid_pos] = obj
	print("📍 Voxel placed at grid:", grid_pos, " | world:", grid_to_world(grid_pos))
	voxel_placed.emit(grid_pos, obj)

func remove_voxel(grid_pos: Vector3i):
	if voxel_grid.erase(grid_pos):
		print("🗑️ Voxel removed from grid:", grid_pos)
		voxel_removed.emit(grid_pos)

func get_voxel(grid_pos: Vector3i):
	return voxel_grid.get(grid_pos)

func has_voxel(grid_pos: Vector3i) -> bool:
	return voxel_grid.has(grid_pos)

func get_all_voxels() -> Array:
	return voxel_grid.keys()

func get_voxel_count() -> int:
	return voxel_grid.size()
