extends Node

# Dictionary with Vector3i keys and VoxelData values
var voxel_grid: Dictionary = {}
var voxel_size: float = 0.1

signal voxel_placed(grid_pos: Vector3i, object: Node3D)
signal voxel_removed(grid_pos: Vector3i)

# --- UNDO/REDO STACKS ---
var undo_stack: Array = []
var redo_stack: Array = []
const MAX_UNDO_STEPS = 250

# --- BATCH TRANSACTION STATE ---
var _current_batch: Array = []
var _is_batching: bool = false

# --- DATA CLASS ---
class VoxelData:
	var object: Node3D
	var shape_type: String
	var rotation: Basis
	var color: Color
	var is_master: bool
	var origin_pos: Vector3

	func _init(obj: Node3D, type: String, rot: Basis, col: Color, master: bool = true):
		object = obj
		shape_type = type
		rotation = rot
		color = col
		is_master = master
		if is_instance_valid(obj):
			origin_pos = obj.global_position
		else:
			origin_pos = Vector3.ZERO

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
	
	
# Add this helper to VoxelDatabase.gd
func _remove_all_references_to_object(obj: Node):
	# We have to scan the grid. 
	# (Optimization: In a real game, you'd store a reverse lookup dict, but this is fine for now)
	var keys_to_remove = []
	
	for pos in voxel_grid:
		var data = voxel_grid[pos]
		# Check if it refers to the same object instance
		if data.object == obj:
			keys_to_remove.append(pos)
			
	for pos in keys_to_remove:
		voxel_grid.erase(pos)
		print("🧹 Cleaned up child voxel at ", pos)

# -------- BATCHING FUNCTIONS (NEW) --------

func start_batch():
	_is_batching = true
	_current_batch.clear()

func end_batch(action_type: String = "place"):
	_is_batching = false
	if _current_batch.is_empty():
		return
	
	# Commit the whole batch as one Undo Step
	# We store a copy of the array so subsequent batches don't overwrite it
	var batch_entry = {
		"action": action_type,
		"items": _current_batch.duplicate()
	}
	
	undo_stack.append(batch_entry)
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front()
	
	# Clear redo stack on new action
	redo_stack.clear()
	_current_batch.clear()

# -------- GRID FUNCTIONS --------

func place_voxel(grid_pos: Vector3i, obj: Node3D, shape_type: String = "cube", color: Color = Color.WHITE, is_undo_redo: bool = false, is_master: bool = true):
	var rotation = obj.global_transform.basis
	var data = VoxelData.new(obj, shape_type, rotation, color, is_master)
	
	voxel_grid[grid_pos] = data
	voxel_placed.emit(grid_pos, obj)
	
	if not is_undo_redo:
		if is_master:
			var entry = {
				"grid_pos": grid_pos,
				"shape_type": shape_type,
				"rotation": rotation,
				"color": color,
				"world_origin": obj.global_position # <--- NEW: Record exact location
			}
			
			if _is_batching:
				_current_batch.append(entry)
			else:
				start_batch()
				_current_batch.append(entry)
				end_batch("place")

func remove_voxel(grid_pos: Vector3i, is_undo_redo: bool = false, destroy_object: bool = true):
	if voxel_grid.has(grid_pos):
		var data = voxel_grid[grid_pos]
		var target_obj = data.object # Reference to the actual node
		
		# Record Undo step BEFORE deleting
		if not is_undo_redo:
			var entry = {
				"grid_pos": grid_pos,
				"shape_type": data.shape_type,
				"rotation": data.rotation,
				"color": data.color,
				"world_origin": data.origin_pos
			}
			if _is_batching:
				_current_batch.append(entry)
			else:
				start_batch()
				_current_batch.append(entry)
				end_batch("remove")
		
		# ⭐ NEW CLEANUP LOGIC ⭐
		if is_instance_valid(target_obj):
			# If we are deleting a Multi-Voxel object, we must remove ALL its grid entries
			# otherwise they become Zombies and block future placement.
			_remove_all_references_to_object(target_obj)
		else:
			# Fallback if object is already dead (zombie cleanup)
			voxel_grid.erase(grid_pos)

		voxel_removed.emit(grid_pos)
		
		if destroy_object:
			if is_instance_valid(target_obj):
				target_obj.queue_free()

# -------- UNDO / REDO SYSTEM --------

func perform_undo(spawner_script: Node):
	if undo_stack.is_empty():
		print("Nothing to undo.")
		return
		
	var last_batch = undo_stack.pop_back()
	redo_stack.append(last_batch) # Move entire batch to redo
	
	print("Undoing Batch:", last_batch.action, " with ", last_batch.items.size(), " items")
	
	var items = last_batch.items
	
	# IMPORTANT: Reverse iteration for Undo is usually safer 
	# (Imagine building a tower: Undo must remove top block first)
	# items.reverse() # Optional, but good practice
	
	if last_batch.action == "place":
		for item in items:
			# Undo placement = Remove it
			remove_voxel(item.grid_pos, true, true)
		
	elif last_batch.action == "remove":
		for item in items:
			# Undo removal = Put it back
			spawner_script.restore_block_from_history(item)

func perform_redo(spawner_script: Node):
	if redo_stack.is_empty():
		print("Nothing to redo.")
		return
		
	var next_batch = redo_stack.pop_back()
	undo_stack.append(next_batch)
	
	print("Redoing Batch:", next_batch.action)
	
	var items = next_batch.items
	
	if next_batch.action == "place":
		for item in items:
			# Redo placement = Put it back
			spawner_script.restore_block_from_history(item)
		
	elif next_batch.action == "remove":
		for item in items:
			# Redo removal = Remove it again
			remove_voxel(item.grid_pos, true, true)

# -------- GETTERS --------
func get_voxel(grid_pos: Vector3i) -> Node3D:
	var data = voxel_grid.get(grid_pos)
	
	if data and is_instance_valid(data.object):
		return data.object
	
	# If we found data but the object is dead, clean up the mess!
	if data and not is_instance_valid(data.object):
		print("⚠️ VoxelDatabase found a zombie node at ", grid_pos, ". Cleaning it up.")
		voxel_grid.erase(grid_pos)
		
	return null

func get_voxel_data(grid_pos: Vector3i) -> VoxelData:
	return voxel_grid.get(grid_pos)
	
# Add this to VoxelDatabase.gd

# Forcefully removes this specific object instance from the entire grid
func cleanup_object_references(obj: Node):
	var positions_to_clear = []
	
	# Scan the grid for any reference to this object
	for pos in voxel_grid:
		var data = voxel_grid[pos]
		# Check if it's the exact same instance OR if the instance is already dead
		if data.object == obj or (is_instance_valid(obj) and data.object == null):
			positions_to_clear.append(pos)
	
	# Remove them
	for pos in positions_to_clear:
		# Pass destroy_object=false because we are holding it, not deleting it!
		remove_voxel(pos, false, false)
		print("🧹 Cleaned up DESYNCED voxel at ", pos)

func has_voxel(grid_pos: Vector3i) -> bool:
	# 1. If the key doesn't exist, it's definitely empty.
	if not voxel_grid.has(grid_pos):
		return false
		
	# 2. The key exists. Let's check the data.
	var data = voxel_grid[grid_pos]
	
	# 3. Check if the object is actually alive
	if is_instance_valid(data.object) and not data.object.is_queued_for_deletion():
		return true
	
	# 4. FOUND A ZOMBIE! 🧟
	# The key exists, but the object is dead/null.
	# Clean it up automatically so the user can build here.
	print("🧟 VoxelDatabase: Auto-cleaned zombie voxel at ", grid_pos)
	voxel_grid.erase(grid_pos)
	
	return false

func get_all_voxels() -> Array:
	return voxel_grid.keys()

func get_voxel_count() -> int:
	return voxel_grid.size()
