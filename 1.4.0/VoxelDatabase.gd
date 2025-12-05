extends Node

# Dictionary with Vector3i keys and VoxelData values
var voxel_grid: Dictionary = {}
var voxel_size: float = 0.1

signal voxel_placed(grid_pos: Vector3i, object: Node3D)
signal voxel_removed(grid_pos: Vector3i)

# --- UNDO/REDO STACKS ---
var undo_stack: Array = []
var redo_stack: Array = []
const MAX_UNDO_STEPS = 50

# --- DATA CLASS ---
class VoxelData:
	var object: Node3D
	var shape_type: String
	var rotation: Basis
	var color: Color # <--- Added Color Storage

	func _init(obj: Node3D, type: String, rot: Basis, col: Color):
		object = obj
		shape_type = type
		rotation = rot
		color = col

# -------- POSITION HELPERS --------
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

# -------- GRID FUNCTIONS --------

# ⭐ UPDATED SIGNATURE: Now accepts Color and UndoFlag
func place_voxel(grid_pos: Vector3i, obj: Node3D, shape_type: String = "cube", color: Color = Color.WHITE, is_undo_redo: bool = false):
	var rotation = obj.global_transform.basis
	var data = VoxelData.new(obj, shape_type, rotation, color)
	
	voxel_grid[grid_pos] = data
	print("📍 Voxel placed at grid:", grid_pos, " type:", shape_type)
	voxel_placed.emit(grid_pos, obj)
	
	if not is_undo_redo:
		# If this is a new user action, clear redo stack and add to undo
		redo_stack.clear()
		_record_action("place", grid_pos, shape_type, rotation, color)

# ⭐ UPDATED SIGNATURE: Now accepts UndoFlag
# VoxelDatabase.gd

# ⭐ UPDATED SIGNATURE: Added 'destroy_object' parameter (defaults to true)
func remove_voxel(grid_pos: Vector3i, is_undo_redo: bool = false, destroy_object: bool = true):
	if voxel_grid.has(grid_pos):
		var data = voxel_grid[grid_pos]
		
		if not is_undo_redo:
			_record_action("remove", grid_pos, data.shape_type, data.rotation, data.color)
			
		voxel_grid.erase(grid_pos)
		print("🗑️ Removed voxel:", grid_pos)
		voxel_removed.emit(grid_pos)
		
		# ⭐ FIX IS HERE: Only destroy if explicitly asked
		if destroy_object and is_instance_valid(data.object):
			data.object.queue_free()

# -------- UNDO / REDO SYSTEM --------

func _record_action(action: String, pos: Vector3i, type: String, rot: Basis, col: Color):
	var entry = {
		"action": action,
		"grid_pos": pos,
		"shape_type": type,
		"rotation": rot,
		"color": col
	}
	undo_stack.append(entry)
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front() 

func perform_undo(spawner_script: Node):
	if undo_stack.is_empty():
		print("Nothing to undo.")
		return
		
	var last_action = undo_stack.pop_back()
	redo_stack.append(last_action)
	
	print("Undoing:", last_action.action)
	
	if last_action.action == "place":
		# Undo placement = Remove it
		remove_voxel(last_action.grid_pos, true)
		
	elif last_action.action == "remove":
		# Undo removal = Put it back
		spawner_script.restore_block_from_history(last_action)

func perform_redo(spawner_script: Node):
	if redo_stack.is_empty():
		print("Nothing to redo.")
		return
		
	var next_action = redo_stack.pop_back()
	undo_stack.append(next_action)
	
	print("Redoing:", next_action.action)
	
	if next_action.action == "place":
		# Redo placement = Put it back
		spawner_script.restore_block_from_history(next_action)
		
	elif next_action.action == "remove":
		# Redo removal = Remove it again
		remove_voxel(next_action.grid_pos, true)

# -------- GETTERS --------
func get_voxel(grid_pos: Vector3i) -> Node3D:
	var data = voxel_grid.get(grid_pos)
	return data.object if data else null

func get_voxel_data(grid_pos: Vector3i) -> VoxelData:
	return voxel_grid.get(grid_pos)

func has_voxel(grid_pos: Vector3i) -> bool:
	return voxel_grid.has(grid_pos)

func get_all_voxels() -> Array:
	return voxel_grid.keys()

func get_voxel_count() -> int:
	return voxel_grid.size()
