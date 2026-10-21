extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
var saved:=false
var loaded:=false
func check(ok: bool,label_: String):
	checks+=1
	if ok:print("ORIGIN PASS: "+label_)
	else:failures+=1;push_error("ORIGIN FAIL: "+label_)
func frames():
	for _i in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
func _ready():
	super._ready()
	get_node("/root/DriveUpload").endpoint=""
	await frames()
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false)
	var hand:=Node3D.new();add_child(hand)
	var id: int=doc.new_sketch(doc.base_plane("Front"))
	doc.set_profile(id,"rectangle",[[0,0],[20,10]],true)
	check(await doc.extrude(id,5,"New"),"create model before repositioning origin")
	var before: Dictionary=doc.snapshot();var old_basis: Basis=Doc.unpack_transform(doc.sketch(id).plane).basis
	doc.checkpoint()
	for viewpoint in [Vector3(0,1.7,0),Vector3(2,1.1,0),Vector3(-2,2.2,-1),Vector3(0,0.5,-3)]:
		wb.camera.global_transform=Transform3D(Basis.from_euler(Vector3(0.3,0.4,0.2)),viewpoint)
		hand.global_position=Vector3(0.2,1.1,-1)
		wb._drag_origin(hand)
		var toward: Vector3=wb.camera.global_position-doc.origin_mm*0.001;toward.y=0
		var front: Transform3D=doc.base_plane("Front");var top: Transform3D=doc.base_plane("Top");var right: Transform3D=doc.base_plane("Right")
		check(front.basis.z.dot(toward.normalized())>0.99999,"Front faces the viewer from different sides")
		check(top.basis.z.is_equal_approx(Vector3.UP) and front.basis.y.is_equal_approx(Vector3.UP),"head pitch and roll never tilt Top or Front")
		check(absf(front.basis.z.dot(right.basis.z))<0.00001 and absf(top.basis.z.dot(right.basis.z))<0.00001,"Right stays perpendicular to Front and Top")
		check(front.origin==doc.origin_mm and top.origin==doc.origin_mm and right.origin==doc.origin_mm,"all base planes keep the same dragged origin")
	var after: Dictionary=doc.snapshot();var translation: Vector3=doc.origin_mm-Vector3(before.origin_mm[0],before.origin_mm[1],before.origin_mm[2])
	var translated_only:=true
	for i in doc.bodies[0].faces.size():
		var a: Array=doc.bodies[0].faces[i];var b: Array=before.bodies[0].faces[i]
		if Vector3(a[0]-b[0],a[1]-b[1],a[2]-b[2]).distance_to(translation)>0.002:translated_only=false
	check(translated_only and Doc.unpack_transform(doc.sketch(id).plane).basis==old_basis,"existing geometry translates as before and existing sketch frames retain their orientation")
	doc.undo();check(doc.snapshot()==before,"one Undo restores origin position and plane heading")
	doc.redo();check(doc.snapshot()==after,"Redo restores origin position and plane heading")
	var restored:=Doc.new();add_child(restored)
	var serialized: Dictionary=JSON.parse_string(JSON.stringify(after))
	check(Doc.validate(serialized).is_empty(),"new heading validates after JSON round trip")
	restored.load_document(serialized)
	check(restored.base_plane("Front").is_equal_approx(doc.base_plane("Front")) and restored.base_plane("Top").basis.z.is_equal_approx(Vector3.UP),"saved heading reloads with Front aligned and Top level")
	serialized.erase("origin_yaw");restored.load_document(serialized)
	check(restored.origin_yaw==0.0 and restored.base_plane("Front").basis==Basis.IDENTITY,"older saves retain their original world-aligned base planes")
	for value in [NAN,INF,"bad",[0],TAU]:
		var corrupt: Dictionary=after.duplicate(true);corrupt.origin_yaw=value
		check(not Doc.validate(corrupt).is_empty(),"malformed saved heading rejects safely")
	restored.queue_free();await get_tree().process_frame
	var heading: float=doc.origin_yaw
	doc.move_origin(doc.origin_mm+Vector3(10,20,30))
	check(doc.origin_yaw==heading,"typed origin coordinate changes retain the heading")
	# New sketches use the actual oriented base frame, not a display-only rotation.
	var new_id: int=doc.new_sketch(doc.base_plane("Front"))
	check(Doc.unpack_transform(doc.sketch(new_id).plane).basis.is_equal_approx(doc.base_plane("Front").basis),"new Front sketch inherits the facing plane for drawing and extrusion")
	# Repeat in a translated, magnified and yawed display frame.
	doc.set_reference_plane({"plane_mm":Doc.pack_transform(Transform3D.IDENTITY),"stage_pose":Doc.pack_transform(Transform3D(Basis(Vector3.UP,0.65),Vector3(0.4,0.2,0.3))),"locked":true,"lock_rotation":false})
	wb.table_view_scale=3.0;wb._update_reference_view()
	wb.camera.global_position=Vector3(-0.8,1.8,0.6);hand.global_position=Vector3(0.3,1.1,-0.7)
	wb._drag_origin(hand)
	var world_origin: Vector3=doc.view_transform*(doc.origin_mm*0.001)
	var world_toward: Vector3=wb.camera.global_position-world_origin;world_toward.y=0
	var world_front: Vector3=(doc.view_transform.basis*doc.base_plane("Front").basis.z).normalized()
	check(world_front.dot(world_toward.normalized())>0.99999,"view zoom and yaw are removed before computing the facing heading")
	check((doc.view_transform.basis*doc.base_plane("Top").basis.z).normalized().is_equal_approx(Vector3.UP),"Top remains physically level in the zoomed display")
	var displayed_front: Transform3D=doc.base_plane("Front");displayed_front.origin*=0.001
	displayed_front=doc.view_transform*displayed_front
	hand.global_transform=Transform3D(displayed_front.basis.orthonormalized(),displayed_front*Vector3(0,0,0.3))
	check(wb.pick_base_plane(hand)=="Front","pointer selection uses the rotated Front plane in the zoomed view")

	# A viewer directly above the origin cannot define a horizontal direction.
	hand.global_transform=Transform3D(Basis.IDENTITY,Vector3(0.3,1.1,-0.7))
	wb.camera.global_position=doc.view_transform*(doc.origin_mm*0.001+Vector3.UP)
	heading=doc.origin_yaw
	wb._drag_origin(hand)
	check(doc.origin_yaw==heading and is_finite(heading),"near-vertical viewing retains the last stable heading")
	doc.view_transform=Transform3D.IDENTITY
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1})
	# An empty workspace with only heading changed must still use the CAD envelope.
	doc.move_origin(doc.origin_mm,true,PI/2)
	var saver=get_node("SaveSystem");saver.save_directory="/private/tmp/abccad-origin-facing-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(saver.save_directory)
	SignalBus.save_finished.connect(func(ok,_message):saved=ok)
	SignalBus.load_finished.connect(func(ok,_message):loaded=ok)
	SignalBus.request_save_game.emit("heading-only")
	var payload=JSON.parse_string(FileAccess.get_file_as_string(saver.save_directory.path_join("heading-only.json")))
	check(saved and payload is Dictionary and payload.cad.has("origin_yaw"),"heading-only workspace saves through the production Save action")
	doc.move_origin(doc.origin_mm,true,0)
	SignalBus.request_load_game.emit("heading-only.json");await frames()
	check(loaded and absf(doc.origin_yaw-PI/2)<0.00001,"production Load restores heading even with no sketches or parts")
	# Exercise the real right-hand trigger path, including its grouped checkpoint.
	var tracker:=XRPositionalTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name="right_hand"
	tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0.7,1.1,-0.8)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("trigger_click",false);tracker.set_input("by_button",false);tracker.set_input("grip",0.0);tracker.set_input("primary",Vector2.ZERO)
	XRServer.add_tracker(tracker)
	wb.camera.global_position=Vector3(0,1.6,0)
	wb.open_panel()
	wb.panel.global_position=Vector3(-3,1.2,-1);wb._remember_panel_pose()
	wb.ui.show_command("origin");wb.set_process(true);await frames()
	before=doc.snapshot();var history: int=doc.undo_steps.size()
	tracker.set_input("trigger_click",true);await frames()
	tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0.9,1.2,-0.9)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await frames()
	check(doc.origin_mm!=Vector3(before.origin_mm[0],before.origin_mm[1],before.origin_mm[2]) and doc.undo_steps.size()==history+1,"native right-trigger drag updates origin and creates only one undo checkpoint")
	var pointer=wb._ray_node(wb.right)
	for contact in [Vector3.ZERO,Vector3(0,-0.42,0),Vector3(0.48,-0.40,0)]:
		wb.panel.global_transform=Transform3D(pointer.global_basis,pointer.global_position-pointer.global_basis.z*0.6-pointer.global_basis*contact)
		wb._remember_panel_pose()
		var previous_origin: Vector3=doc.origin_mm
		tracker.set_pose("default",Transform3D(Basis.IDENTITY,wb.right.position+Vector3(0.01,0.01,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await frames()
		var expected: Vector3=(doc.view_transform.affine_inverse()*(wb.right.global_position-wb.right.global_basis.z*0.25))*1000.0
		check(doc.origin_mm.distance_to(expected)<0.01 and doc.origin_mm!=previous_origin,"held origin follows through studio contact "+str(contact))
		check(wb.panel_handles.active_hand==null and doc.undo_steps.size()==history+1,"studio handle cannot steal active origin drag or add undo steps")
		check(pointer._ignored_studio_bodies.size()==3 and pointer.last_target!=wb.panel.get_node("StaticBody3D"),"dragging pointer ignores studio surface and handles")
		check(not wb.world_drag_active(wb.left) and wb._ray_node(wb.left)._ignored_studio_bodies.is_empty(),"other hand retains studio interaction")
	tracker.set_input("trigger_click",false);await frames();after=doc.snapshot()
	check(not wb._moving_origin and pointer._ignored_studio_bodies.is_empty(),"release over studio ends capture and restores pointer collision")
	tracker.set_pose("default",Transform3D(Basis.IDENTITY,wb.right.position+Vector3(0.05,0,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await frames()
	check(doc.snapshot()==after,"released origin stays still when the controller moves away")
	wb.camera.global_position+=Vector3(1,0.5,0);await frames()
	check(doc.snapshot()==after,"planes keep their released heading when the viewer moves")
	doc.undo();check(doc.snapshot()==before,"native drag undo restores the complete prior origin state")
	doc.redo();check(doc.snapshot()==after,"native drag redo restores the released state")
	XRServer.remove_tracker(tracker);hand.queue_free()
	print("ORIGIN RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
