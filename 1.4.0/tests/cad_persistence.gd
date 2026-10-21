extends Node3D
const Document=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
var saved:=false
var loaded:=false
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1; push_error("CAD SAVE FAIL: "+label)
	else: print("CAD SAVE PASS: "+label)
func frames():
	await get_tree().process_frame
	await get_tree().process_frame
func _ready():
	var player=preload("res://player.tscn").instantiate()
	add_child(player)
	var left=player.get_node("LeftHand")
	var saver=preload("res://SaveSystem.gd").new()
	saver.save_directory="/private/tmp/abccad-cad-persistence-"+str(OS.get_process_id())
	add_child(saver)
	SignalBus.save_finished.connect(func(ok,_message):saved=ok)
	SignalBus.load_finished.connect(func(ok,_message):loaded=ok)
	var doc=Document.new()
	add_child(doc)
	var id: int=doc.new_sketch(doc.base_plane("Top"))
	doc.set_profile(id,"rectangle",[[0,0],[20.123,15.321]])
	doc.add_inference(id,0,{"kind":"origin"})
	check(await doc.extrude(id,10,"New"),"create metric CAD solid")
	left.restore_block_from_history({"grid_pos":Vector3i(0,10,0),"shape_type":"cube","rotation":Basis.IDENTITY,"color":Color.RED,"world_origin":Vector3(0,1,0)})
	var baseline: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	SignalBus.request_save_game.emit("mixed-cad")
	check(saved,"mixed CAD and legacy block save")
	var payload=JSON.parse_string(FileAccess.get_file_as_string(saver.save_directory.path_join("mixed-cad.json")))
	check(payload is Dictionary and payload.format=="abccad-cad-v1" and payload.blocks.size()==1,"versioned envelope preserves legacy cells")
	doc.move_origin(Vector3(150,900,-400))
	SignalBus.request_load_game.emit("mixed-cad.json")
	await frames()
	check(loaded and VoxelDatabase.get_voxel_count()==1,"mixed document restores both systems")
	check(JSON.parse_string(JSON.stringify(doc.snapshot()))==baseline,"all CAD vertices sketches constraints and origin round-trip exactly")
	var corrupt: Dictionary=payload.duplicate(true)
	corrupt.cad.sketches[0].constraints[0].kind="unknown"
	var file:=FileAccess.open(saver.save_directory.path_join("bad-cad.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt));file.close()
	SignalBus.request_load_game.emit("bad-cad.json")
	check(not loaded and JSON.parse_string(JSON.stringify(doc.snapshot()))==baseline and VoxelDatabase.get_voxel_count()==1,"bad CAD data leaves entire mixed build intact")
	var exporter=preload("res://VoxelExporter.gd").new()
	add_child(exporter)
	var mesh: ArrayMesh=exporter.build_export_mesh()
	check(mesh!=null and mesh.get_faces().size()==72,"shared export includes one CAD solid and one block")
	var mm: ArrayMesh=exporter.build_export_mesh(1000.0)
	var stl_path: String=saver.save_directory.path_join("mixed-mm.stl")
	check(STLIO.Exporter.SaveToPath(mm,stl_path)==OK,"write actual millimeter binary STL")
	var bytes:=FileAccess.get_file_as_bytes(stl_path)
	var mins:=Vector3(INF,INF,INF);var maxs:=Vector3(-INF,-INF,-INF)
	for i in bytes.decode_u32(80):
		for j in 3:
			var at:=84+i*50+12+j*12
			var p:=Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8))
			mins=mins.min(p);maxs=maxs.max(p)
	check((maxs-mins).is_equal_approx(Vector3(100,210,715.321)),"binary STL dimensions use millimeters, including 100 mm block")
	# Legacy array saves remain loadable and replace the CAD document too.
	file=FileAccess.open(saver.save_directory.path_join("old.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(payload.blocks));file.close()
	SignalBus.request_load_game.emit("old.json")
	await frames()
	check(loaded and doc.bodies.is_empty() and doc.sketches.is_empty() and VoxelDatabase.get_voxel_count()==1,"legacy array loads cleanly and clears stale CAD")
	doc.move_origin(Vector3(50,600,-800))
	SignalBus.request_save_game.emit("origin-only")
	check(saved,"save moved origin before any sketch or solid")
	doc.move_origin(Vector3.ZERO)
	SignalBus.request_load_game.emit("origin-only.json")
	await frames()
	check(loaded and doc.origin_mm.is_equal_approx(Vector3(50,600,-800)),"empty CAD workspace retains moved origin across reload")
	print("CAD PERSISTENCE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
