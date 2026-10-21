extends "res://main.gd"
const Document=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
var save_ok:=false
var load_ok:=false
var io_message:=""
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error("CAD PICKUP FAIL: "+label)
	else: print("CAD PICKUP PASS: "+label)
func frames():
	for _i in 5:
		await get_tree().physics_frame
		await get_tree().process_frame
func tracker(name_: String, position_: Vector3) -> XRPositionalTracker:
	var t:=XRPositionalTracker.new()
	t.type=XRServer.TRACKER_CONTROLLER
	t.name=name_
	t.set_pose("default",Transform3D(Basis.IDENTITY,position_),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	t.set_input("grip",0.0)
	t.set_input("primary",Vector2.ZERO)
	XRServer.add_tracker(t)
	return t
func _ready():
	var lt:=tracker("left_hand",Vector3(-0.2,1.2,-0.6))
	var rt:=tracker("right_hand",Vector3(0.2,1.2,-0.6))
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	var left=get_node("XROrigin3D/LeftHand")
	var right=get_node("XROrigin3D/RightHand")
	var saver=get_node("SaveSystem")
	saver.save_directory="/private/tmp/abccad-pickup-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(saver.save_directory)
	SignalBus.save_finished.connect(func(ok,text): save_ok=ok;io_message=text)
	SignalBus.load_finished.connect(func(ok,text): load_ok=ok;io_message=text)
	var id: int=doc.new_sketch(doc.base_plane("Front"))
	doc.set_profile(id,"rectangle",[[0,0],[20,15]])
	check(await doc.extrude(id,10,"New"),"create pickable 40 x 30 x 10 mm solid")
	await frames()
	var body_id: int=doc.bodies[0].id
	saver._save_game("before")
	check(save_ok,"initial CAD placement saves")
	var part=doc.get_node("Part_"+str(body_id))
	check(part is XRToolsPickable and part.freeze and part.collision_layer==4,"extruded solid has frozen pickup hull")
	check(not part.is_in_group("abccad_blocks"),"CAD solid remains outside voxel grid")
	for source in [right,left]:
		var destination=left if source==right else right
		var before: Dictionary=doc.snapshot()
		source.my_pickup_function._pick_up_object(part)
		await frames()
		check(source.my_pickup_function.picked_up_object==part and doc.busy,"pickup starts placement transaction from "+source.name)
		saver._save_game("held")
		check(not save_ok and "Release CAD" in io_message,"save clearly rejects moving part")
		var held_state: Dictionary=doc.snapshot()
		saver._load_game("before.json")
		check(not load_ok and doc.snapshot()==held_state,"load cannot replace held part")
		check(not await doc.dimension(id,"width",50),"dimension edits blocked while part held")
		var pose:=Transform3D(Basis.from_euler(Vector3(0.2,0.5,-0.3)),Vector3(0.11,1.26,-0.43))
		# Exercise the same global transform written by the XR grab driver.
		part.global_transform=pose
		part._sync_pose()
		var moved: Dictionary=doc.snapshot()
		check(moved!=before,"moving and rotating updates document geometry")
		check(absf(Document.volume(doc.bodies[0].faces)-12000)<1,"pickup preserves metric volume")
		var plane: Transform3D=Document.unpack_transform(doc.sketch(id).plane)
		check(not plane.is_equal_approx(Document.unpack_transform(before.sketches[0].plane)),"attached sketch follows moved solid")
		destination.my_pickup_function._pick_up_object(part)
		await frames()
		check(destination.my_pickup_function.picked_up_object==part and source.my_pickup_function.picked_up_object==null,"hand swap clears old pickup reference")
		check(doc.busy and part.is_picked_up(),"hand swap keeps transaction open")
		destination.my_pickup_function.drop_object()
		await frames()
		check(not doc.busy and doc.active_grabs.is_empty() and part.freeze,"final release freezes part and unlocks document")
		check(left.held_cube==null and right.held_cube==null,"release clears both hand references")
		var placed: Dictionary=doc.snapshot()
		doc.undo()
		await frames()
		check(doc.snapshot()==before,"undo restores complete pre-grab placement")
		doc.redo()
		await frames()
		check(doc.snapshot()==placed,"redo restores complete moved placement")
		part=doc.get_node("Part_"+str(body_id))
	# Rebuilding feature history after movement must use transformed sketch planes.
	var moved_plane: Transform3D=Document.unpack_transform(doc.sketch(id).plane)
	check(await doc.dimension(id,"width",50),"dimension edit rebuilds a moved and rotated solid")
	check(absf(Document.volume(doc.bodies[0].faces)-15000)<2,"rebuilt moved solid retains expected dimensions")
	check(Document.unpack_transform(doc.sketch(id).plane).is_equal_approx(moved_plane),"dimension edit keeps moved sketch plane")
	var current: Dictionary=doc.snapshot()
	saver._save_game("moved")
	check(save_ok,"moved part saves after release")
	saver._load_game("moved.json")
	await frames()
	check(load_ok and JSON.parse_string(JSON.stringify(doc.snapshot()))==JSON.parse_string(JSON.stringify(current)),"moved part reload preserves solid and feature placements")
	check(Document.validate(current).is_empty(),"moved document validates")
	var invalid:=current.duplicate(true)
	invalid.bodies[0].color="invalid"
	check(not Document.validate(invalid).is_empty(),"malformed saved part color rejected")
	var exporter=preload("res://VoxelExporter.gd").new()
	add_child(exporter)
	var exported: PackedVector3Array=exporter.build_export_mesh(1000).get_faces()
	var mismatch:=0.0
	for vertex in exported:
		var closest:=INF
		for point in doc.bodies[0].faces:
			closest=minf(closest,vertex.distance_to(Vector3(point[0],point[1],point[2])))
		mismatch=maxf(mismatch,closest)
	check(exported.size()==doc.bodies[0].faces.size() and mismatch<0.001,"STL geometry matches moved and rotated body in mm")
	check(VoxelDatabase.get_voxel_count()==0,"moving CAD parts never populates legacy voxel grid")
	# The actual XRTools hand node scales with world scale. Drive real physics
	# rather than assigning the desired object pose manually as above.
	for view_scale in [0.2,1.0,8.43]:
		XRServer.world_scale=view_scale
		await frames()
		for source in [left,right]:
			var pickup=source.my_pickup_function
			for ranged in [false,true]:
				part=doc.get_children().filter(func(node): return node.get_meta("cad_body_id",-1)==body_id)[0]
				var before_pose: Transform3D=part.global_transform
				var local_scale: Vector3=part.get_node("MeshInstance3D").scale
				var volume: float=Document.volume(doc.bodies[0].faces)
				pickup._object_in_grab_area.erase(part)
				if not ranged: pickup._object_in_grab_area.append(part)
				pickup._pick_up_object(part)
				if not ranged: pickup._object_in_grab_area.erase(part)
				await frames()
				check(part.global_basis.get_scale().is_equal_approx(Vector3.ONE),"real grab driver keeps rigid root at scale %s, %s, ranged %s" % [view_scale,source.name,ranged])
				check(part.get_node("MeshInstance3D").scale.is_equal_approx(local_scale) and part.is_visible_in_tree(),"grab preserves visible mesh scale")
				var expected: Vector3=pickup.global_position if ranged else before_pose.origin
				check(part.global_position.distance_to(expected)<0.001,"scaled hand does not throw part away on pickup")
				pickup.drop_object()
				await frames()
				check(absf(Document.volume(doc.bodies[0].faces)-volume)<2,"scaled pickup/release preserves metric solid volume")
	XRServer.world_scale=1.0
	XRServer.remove_tracker(lt)
	XRServer.remove_tracker(rt)
	print("CAD PICKUP RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
