extends Node

# Path where saves are stored
const SAVE_DIR = "user://saves/"

func _ready():
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
		
	SignalBus.request_save_game.connect(_save_game)
	SignalBus.request_load_game.connect(_load_game)

func _save_game(filename_override: String = ""):
	var filename = filename_override
	
	# If no name provided, generate timestamp
	if filename == "":
		filename = "save_" + Time.get_datetime_string_from_system().replace(":", "-") + ".json"
	
	# Make sure it ends in .json
	if not filename.ends_with(".json"):
		filename += ".json"
		
	var full_path = SAVE_DIR + filename
	
	# 1. GATHER DATA
	# We want an array of dictionaries.
	var save_data = []
	var grid_keys = VoxelDatabase.get_all_voxels()
	
	for grid_pos in grid_keys:
		var data = VoxelDatabase.get_voxel_data(grid_pos)
		
		# Only save "Master" blocks. 
		# If a block is 2x2, we only save the origin, not the 3 ghost blocks.
		if data.is_master:
			var item = {
				"x": grid_pos.x,
				"y": grid_pos.y,
				"z": grid_pos.z,
				"type": data.shape_type,
				"col": data.color.to_html(), # Convert Color to Hex String
				# Serialize Basis (Rotation) as an array of 9 floats
				"rot": [
					data.rotation.x.x, data.rotation.x.y, data.rotation.x.z,
					data.rotation.y.x, data.rotation.y.y, data.rotation.y.z,
					data.rotation.z.x, data.rotation.z.y, data.rotation.z.z
				]
			}
			save_data.append(item)
			
	# 2. WRITE TO FILE
	var json_string = JSON.stringify(save_data, "\t") # \t makes it readable
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	
	if file:
		file.store_string(json_string)
		file.close()
		print("💾 Game saved successfully to: ", full_path)
	else:
		print("❌ Failed to save game! Error: ", FileAccess.get_open_error())


func _load_game(filename: String):
	var full_path = SAVE_DIR + filename
	
	if not FileAccess.file_exists(full_path):
		print("❌ Save file not found: ", full_path)
		return

	# 1. READ FILE
	var file = FileAccess.open(full_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	
	if error != OK:
		print("❌ JSON Parse Error: ", json.get_error_message())
		return
		
	var loaded_data = json.data
	if typeof(loaded_data) != TYPE_ARRAY:
		print("❌ Invalid save file format")
		return

	print("📂 Loading ", loaded_data.size(), " blocks...")

	# 2. CLEAR CURRENT WORLD
	_clear_world()

	# 3. RECONSTRUCT BLOCKS
	# We need to turn off batching momentarily or treat this as one huge batch
	# Generally, you clear the Undo stack when loading a new game.
	VoxelDatabase.undo_stack.clear()
	VoxelDatabase.redo_stack.clear()

	for item in loaded_data:
		var pos = Vector3i(item.x, item.y, item.z)
		var type = item.type
		var color = Color.html(item.col)
		
		# Reconstruct Basis
		var r = item.rot
		var basis = Basis(
			Vector3(r[0], r[1], r[2]),
			Vector3(r[3], r[4], r[5]),
			Vector3(r[6], r[7], r[8])
		)
		
		# 🚨 CRITICAL STEP:
		# The SaveSystem doesn't know how to spawn scenes.
		# We must ask the Main Scene (where your spawner logic is) to do it.
		SignalBus.request_rebuild_block.emit(pos, type, basis, color)

	print("✅ Load Complete!")

func _clear_world():
	# Iterate backwards through keys to avoid modification issues, 
	# though VoxelDatabase.remove_voxel handles this safely.
	var all_voxels = VoxelDatabase.get_all_voxels()
	for pos in all_voxels:
		# Use internal removal to skip undo history logging during clear
		VoxelDatabase.remove_voxel(pos, true, true)
	print("🧹 World cleared.")
