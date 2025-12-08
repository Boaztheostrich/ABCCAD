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
	if filename == "":
		filename = "save_" + Time.get_datetime_string_from_system().replace(":", "-") + ".json"
	if not filename.ends_with(".json"):
		filename += ".json"
	var full_path = SAVE_DIR + filename
	
	# 1. GATHER DATA
	var save_data = []
	var grid_keys = VoxelDatabase.get_all_voxels()
	
	for grid_pos in grid_keys:
		var data = VoxelDatabase.get_voxel_data(grid_pos)
		
		# SAVE EVERYTHING (Masters and Children)
		var item = {
			"x": grid_pos.x,
			"y": grid_pos.y,
			"z": grid_pos.z,
			"type": data.shape_type,
			"col": data.color.to_html(),
			"is_master": data.is_master, # <--- NEW: Save this flag
			# We save origin_pos so children can find their master's location if needed
			"origin_x": data.origin_pos.x,
			"origin_y": data.origin_pos.y,
			"origin_z": data.origin_pos.z,
			"rot": [
				data.rotation.x.x, data.rotation.x.y, data.rotation.x.z,
				data.rotation.y.x, data.rotation.y.y, data.rotation.y.z,
				data.rotation.z.x, data.rotation.z.y, data.rotation.z.z
			]
		}
		save_data.append(item)
			
	# Sort to keep file consistent (optional, but nice)
	save_data.sort_custom(func(a, b): return a.y < b.y)

	# 2. WRITE TO FILE
	var json_string = JSON.stringify(save_data, "\t")
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

	print("📂 Loading ", loaded_data.size(), " voxels...")

	# 2. CLEAR CURRENT WORLD
	_clear_world()
	
	# Clear Undo/Redo stacks on load
	VoxelDatabase.undo_stack.clear()
	VoxelDatabase.redo_stack.clear()

	# 3. FIRST PASS: SPAWN MASTERS
	# We need to spawn the physical objects first so the children have something to point to.
	
	# Dictionary to store reference to the spawned Node3D objects using origin position as key
	# Key: String(Vector3), Value: Node3D
	var master_registry = {} 

	for item in loaded_data:
		if item.is_master:
			var pos = Vector3i(item.x, item.y, item.z)
			var type = item.type
			var color = Color.html(item.col)
			var basis = Basis(
				Vector3(item.rot[0], item.rot[1], item.rot[2]),
				Vector3(item.rot[3], item.rot[4], item.rot[5]),
				Vector3(item.rot[6], item.rot[7], item.rot[8])
			)
			
			# ⭐ RECONSTRUCT THE VECTOR3 HERE
			var exact_origin = Vector3(item.origin_x, item.origin_y, item.origin_z)
			
			# Pass it to the signal
			SignalBus.request_rebuild_block.emit(pos, type, basis, color, exact_origin)
			
			# Signal LeftHand to spawn the object
			SignalBus.request_rebuild_block.emit(pos, type, basis, color)
			
			# Wait a tiny bit for the object to be registered? 
			# No, SignalBus is immediate in this case, but we need to grab the object 
			# directly from the Database because 'rebuild_block' spawns and places it.
			var spawned_obj = VoxelDatabase.get_voxel(pos)
			
			if spawned_obj:
				# Use the string version for keys, but we sent the real Vector3 above
				var origin_key = str(exact_origin.round()) 
				master_registry[origin_key] = spawned_obj

	# 4. SECOND PASS: REGISTER CHILDREN
	# Now we fill in the gaps. Since 'request_rebuild_block' spawns the Master 
	# and calls 'place_voxel', the master slot is already filled. 
	# We just need to manually place the child slots.
	
	for item in loaded_data:
		if not item.is_master:
			var grid_pos = Vector3i(item.x, item.y, item.z)
			var origin_key = str(Vector3(item.origin_x, item.origin_y, item.origin_z).round())
			
			var master_obj = master_registry.get(origin_key)
			
			if master_obj:
				var type = item.type
				var color = Color.html(item.col)
				var basis = Basis(
					Vector3(item.rot[0], item.rot[1], item.rot[2]),
					Vector3(item.rot[3], item.rot[4], item.rot[5]),
					Vector3(item.rot[6], item.rot[7], item.rot[8])
				)
				
				# Manually register the child without spawning a new mesh
				# We pass 'false' for is_master
				VoxelDatabase.place_voxel(grid_pos, master_obj, type, color, true, false)
			else:
				print("⚠️ Orphan child voxel found at ", grid_pos)

	print("✅ Load Complete!")

func _clear_world():
	var all_voxels = VoxelDatabase.get_all_voxels()
	for pos in all_voxels:
		VoxelDatabase.remove_voxel(pos, true, true)
	print("🧹 World cleared.")
