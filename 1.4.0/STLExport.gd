extends RefCounted
## Serialize once; use app-writable storage on Android instead of assuming public
## Downloads access. Desktop exports keep Downloads and fall back if unavailable.
static func directories(platform: String,downloads: String,user_data: String) -> Array[String]:
	var app:=user_data.path_join("exports")
	if platform=="Android" or downloads.is_empty(): return [app]
	var result: Array[String]=[downloads]
	if downloads!=app: result.append(app)
	return result

const Solid=preload("res://cad/CADSolidValidation.gd")
const Doc=preload("res://cad/CADDocument.gd")

static func save(mesh: Mesh,prefix: String,locations: Array[String]=[],parts: Array[Mesh]=[]) -> Dictionary:
	if mesh==null: return {"error":ERR_INVALID_DATA,"path":""}
	# Validate each assembly part independently: separate touching blocks remain
	# separate closed shells, rather than becoming one welded CAD body.
	var candidates: Array[Mesh]=[]
	candidates.assign(parts)
	if candidates.is_empty():candidates.append(mesh)
	for index in candidates.size():
		var solid_error:=Solid.error(Solid.clean_faces(Doc.faces_from_mesh(candidates[index])))
		if not solid_error.is_empty():
			return {"error":ERR_INVALID_DATA,"path":"","detail":"Part %d: %s" % [index+1,solid_error]}
	var bytes: Variant=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(Solid.clean_faces(Doc.faces_from_mesh(mesh))))
	if not bytes is PackedByteArray: return {"error":bytes,"path":""}
	var destinations:=locations
	if destinations.is_empty(): destinations=directories(OS.get_name(),OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS),OS.get_user_data_dir())
	var filename:=prefix+Time.get_datetime_string_from_system().replace(":","-")+"_"+str(Time.get_ticks_usec())+".stl"
	var error: Error=ERR_CANT_CREATE
	for directory in destinations:
		error=DirAccess.make_dir_recursive_absolute(directory)
		if error!=OK: continue
		var path:=directory.path_join(filename)
		# Keep previous exports intact even if clocks reset or two exports coincide.
		while FileAccess.file_exists(path):
			path=directory.path_join(filename.get_basename()+"_"+str(Time.get_ticks_usec())+".stl")
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null:
			error=FileAccess.get_open_error()
			continue
		file.store_buffer(bytes)
		file.flush()
		error=file.get_error()
		file.close()
		if error==OK:
			var loop := Engine.get_main_loop() as SceneTree
			if loop != null:
				var uploader := loop.root.get_node_or_null("DriveUpload")
				if uploader != null: uploader.call_deferred("enqueue", path)
			return {"error":OK,"path":path,"app_storage":directory==OS.get_user_data_dir().path_join("exports")}
		DirAccess.remove_absolute(path)
	return {"error":error,"path":""}

static func message(result: Dictionary,millimeters: bool) -> String:
	if result.has("detail"): return "STL export blocked. "+String(result.detail)
	if result.error!=OK: return "STL export failed: "+error_string(result.error)+". Try again after freeing storage."
	var label: String="STL saved in mm" if millimeters else "STL saved"
	if result.get("app_storage",false): label+=" · app exports"
	return label+" · "+String(result.path).get_file()
