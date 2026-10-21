extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var doc=preload("res://cad/CADDocument.gd").new()
	root.add_child(doc)
	var sid: int=doc.new_sketch(Transform3D(Basis.IDENTITY,Vector3(30,980,-650)))
	doc.set_profile(sid,"circle",[[0,0],[80,0]])
	if not await doc.extrude(sid,20,"New"): quit(1);return
	var plane:=Transform3D(Basis(Vector3.RIGHT,Vector3.FORWARD,Vector3.UP),Vector3(0,900,-500))
	var stage:=plane
	stage.origin*=0.001
	doc.set_reference_plane({"plane_mm":doc.pack_transform(plane),"stage_pose":doc.pack_transform(stage),"locked":true,"lock_rotation":false})
	var args:=OS.get_cmdline_user_args()
	var destination: String=args[0] if not args.is_empty() else "/private/tmp/abccad-table-native/preview-load-test.json"
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file=FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify({"format":"abccad-cad-v1","blocks":[],"cad":doc.snapshot()}))
	file.close()
	print("Large preview fixture written")
	quit()
