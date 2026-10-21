extends Node

const SAVE_DIR = "user://saves/"
# Exported so regression tests can use an isolated temporary directory.
@export var save_directory: String = SAVE_DIR

func _ready():
	DirAccess.make_dir_recursive_absolute(save_directory)
	SignalBus.request_save_game.connect(_save_game)
	SignalBus.request_load_game.connect(_load_game)

func _save_game(filename_override: String = ""):
	var filename := filename_override
	if filename.is_empty():
		filename = "save_" + Time.get_datetime_string_from_system().replace(":", "-") + "_" + str(Time.get_ticks_usec()) + ".json"
	if not filename.ends_with(".json"):
		filename += ".json"
	if filename != filename.get_file():
		SignalBus.save_finished.emit(false, "Invalid save filename.")
		return
	var cad = get_tree().get_first_node_in_group("cad_document")
	if cad != null and cad.busy:
		SignalBus.save_finished.emit(false, "Release CAD parts before saving." if not cad.active_grabs.is_empty() else "Wait for the CAD operation to finish before saving.")
		return
	var save_data: Array = []
	for grid_pos in VoxelDatabase.get_all_voxels():
		var data = VoxelDatabase.get_voxel_data(grid_pos)
		if not is_instance_valid(data.object) or data.object.is_queued_for_deletion():
			continue
		save_data.append({
			"x": grid_pos.x, "y": grid_pos.y, "z": grid_pos.z,
			"type": data.shape_type, "col": data.color.to_html(),
			"is_master": data.is_master,
			# All cells belonging to one object share this identifier.
			"object_id": str(data.object.get_instance_id()),
			"origin_x": data.origin_pos.x, "origin_y": data.origin_pos.y, "origin_z": data.origin_pos.z,
			"rot": [data.rotation.x.x, data.rotation.x.y, data.rotation.x.z,
				data.rotation.y.x, data.rotation.y.y, data.rotation.y.z,
				data.rotation.z.x, data.rotation.z.y, data.rotation.z.z]
		})
	var file := FileAccess.open(save_directory.path_join(filename), FileAccess.WRITE)
	if file == null:
		SignalBus.save_finished.emit(false, "Could not write save (%s)." % FileAccess.get_open_error())
		return
	var payload: Variant = save_data
	if cad != null and (not cad.bodies.is_empty() or not cad.sketches.is_empty() or not cad.reference_plane.is_empty() or cad.origin_mm != Vector3(0,1150,-650) or cad.origin_yaw != 0.0):
		payload = {"format":"abccad-cad-v1","blocks":save_data,"cad":cad.snapshot()}
	file.store_string(JSON.stringify(payload, "\t"))
	var write_error := file.get_error()
	file.close()
	SignalBus.save_finished.emit(write_error == OK, "Saved " + filename if write_error == OK else "Could not finish writing save.")

# Old saves have no object_id. Match their exact stored origin and shape rather
# than rounding positions to metres, which merged adjacent objects.
func _object_key(item: Dictionary) -> String:
	if item.has("object_id"):
		return "id:" + str(item.object_id)
	return "legacy:" + JSON.stringify([item.origin_x, item.origin_y, item.origin_z, item.type])

func _grid_pos(item: Dictionary) -> Vector3i:
	return Vector3i(item.x, item.y, item.z)

func _basis(item: Dictionary) -> Basis:
	return Basis(Vector3(item.rot[0], item.rot[1], item.rot[2]),
		Vector3(item.rot[3], item.rot[4], item.rot[5]),
		Vector3(item.rot[6], item.rot[7], item.rot[8]))

func _validate_save(value: Variant, scenes: Array[PackedScene]) -> String:
	if not value is Array: return "Save must contain an array of blocks."
	var masters: Dictionary = {}
	var cells: Dictionary = {}
	for item in value:
		if not item is Dictionary: return "Invalid block record."
		for key in ["x", "y", "z", "type", "col", "is_master", "origin_x", "origin_y", "origin_z", "rot"]:
			if not item.has(key): return "Missing block field: " + key
		for key in ["x", "y", "z", "origin_x", "origin_y", "origin_z"]:
			if not (item[key] is float or item[key] is int) or not is_finite(float(item[key])):
				return "Invalid block coordinate."
		for key in ["x", "y", "z"]:
			if float(item[key]) != roundf(float(item[key])): return "Invalid grid coordinate."
		if not item.type is String or not item.col is String or not item.is_master is bool:
			return "Invalid block properties."
		if not Color.html_is_valid(item.col): return "Invalid block color."
		if not item.rot is Array or item.rot.size() != 9: return "Invalid block rotation."
		for component in item.rot:
			if not (component is float or component is int) or not is_finite(float(component)):
				return "Invalid block rotation."
		if absf(_basis(item).determinant()) < 0.00001: return "Invalid block rotation."
		if BlockInteractions.find_scene(scenes, item.type) == null:
			return "Unknown block type: " + item.type
		var pos := _grid_pos(item)
		if cells.has(pos): return "Multiple records occupy the same cell."
		cells[pos] = true
		var key := _object_key(item)
		if item.is_master:
			if masters.has(key): return "Multiple blocks share an identifier."
			masters[key] = item
	for item in value:
		var master = masters.get(_object_key(item))
		if master == null: return "Block has no master record."
		if item.type != master.type or item.rot != master.rot or item.col != master.col:
			return "Inconsistent block records."
	return ""

func _load_game(filename: String):
	if filename != filename.get_file():
		SignalBus.load_finished.emit(false, "Invalid save filename.")
		return
	var file := FileAccess.open(save_directory.path_join(filename), FileAccess.READ)
	if file == null:
		SignalBus.load_finished.emit(false, "Could not open save.")
		return
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		SignalBus.load_finished.emit(false, "Could not read save: " + json.get_error_message())
		return
	var block_records: Variant = json.data
	var cad_data: Dictionary = {"version":1,"bodies":[],"sketches":[],"next_id":1}
	var cad = get_tree().get_first_node_in_group("cad_document")
	if cad != null and cad.busy:
		SignalBus.load_finished.emit(false,"Release CAD parts before loading." if not cad.active_grabs.is_empty() else "Wait for the CAD operation to finish before loading.")
		return
	if json.data is Dictionary:
		if json.data.get("format")!="abccad-cad-v1" or cad==null:
			SignalBus.load_finished.emit(false,"CAD document loader is unavailable or format is unknown.")
			return
		var error: String = preload("res://cad/CADDocument.gd").validate(json.data.get("cad"))
		if not error.is_empty():
			SignalBus.load_finished.emit(false,error)
			return
		cad_data=json.data.cad
		block_records=json.data.get("blocks")
	var controllers := get_tree().get_nodes_in_group("block_controllers")
	var spawner: Node = null
	for controller in controllers:
		if controller.has_method("restore_block_from_history"):
			spawner = controller
			break
	if spawner == null:
		SignalBus.load_finished.emit(false, "Block loader is unavailable.")
		return
	var validation_error := _validate_save(block_records, spawner.block_scenes)
	if not validation_error.is_empty():
		SignalBus.load_finished.emit(false, validation_error)
		return
	# Invalid files leave the current build intact.
	_clear_world()
	VoxelDatabase.undo_stack.clear()
	VoxelDatabase.redo_stack.clear()
	var registry: Dictionary = {}
	var footprints: Dictionary = {}
	for item in block_records:
		if item.is_master:
			var pos := _grid_pos(item)
			var origin := Vector3(item.origin_x, item.origin_y, item.origin_z)
			SignalBus.request_rebuild_block.emit(pos, item.type, _basis(item), Color.html(item.col), origin)
			var obj := VoxelDatabase.get_voxel(pos)
			if obj == null:
				SignalBus.load_finished.emit(false, "Could not restore block.")
				return
			registry[_object_key(item)] = obj
			footprints[_object_key(item)] = []
	for item in block_records:
		var key := _object_key(item)
		var pos := _grid_pos(item)
		var obj: Node3D = registry[key]
		footprints[key].append(pos)
		if not item.is_master:
			VoxelDatabase.place_voxel(pos, obj, item.type, Color.html(item.col), true, false)
	# Loaded blocks need their footprint for subsequent grabs and moves.
	for key in registry:
		for child in registry[key].get_children():
			if "last_grid_positions" in child:
				child.last_grid_positions.assign(footprints[key])
	if cad != null: cad.load_document(cad_data)
	SignalBus.load_finished.emit(true, "Loaded " + filename)

func _clear_world():
	for pos in VoxelDatabase.get_all_voxels():
		VoxelDatabase.remove_voxel(pos, true, true)
	# Unplaced/held blocks are not in the grid. Clear them too, including any
	# controller state, so loading replaces the whole build.
	for block in get_tree().get_nodes_in_group("abccad_blocks"):
		if not block.is_queued_for_deletion():
			if block.has_method("drop"): block.drop()
			VoxelDatabase.cleanup_object_references(block)
			block.queue_free()
	for controller in get_tree().get_nodes_in_group("block_controllers"):
		controller.held_cube = null
