extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
const Export=preload("res://STLExport.gd")
class TestXR extends XRInterfaceExtension:
	var camera_pose:=Transform3D.IDENTITY
	func _get_name() -> StringName: return &"ReadinessTestXR"
	func _is_initialized() -> bool: return true
	func _get_camera_transform() -> Transform3D: return camera_pose
var checks:=0
var failures:=0
var export_text:=""
var export_ok:=false
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error("HEADSET FAIL: "+label)
	else: print("HEADSET PASS: "+label)
func frames():
	for _i in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
func _ready():
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	var android_paths:=Export.directories("Android","/public/Download","/private/app/files")
	check(android_paths==["/private/app/files/exports"],"Android exports never assume public storage permission")
	check(Export.directories("macOS","/Downloads","/app")==["/Downloads","/app/exports"],"desktop retains Downloads with an app-data fallback")
	check(Export.directories("Linux","","/app")==["/app/exports"],"missing Downloads falls back to writable app storage")
	var folder:="/private/tmp/abccad-headset-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var blocked:=folder.path_join("not-a-directory")
	var sentinel:=FileAccess.open(blocked,FileAccess.WRITE)
	sentinel.store_string("keep this existing file")
	sentinel.close()
	var id: int=doc.new_sketch(doc.base_plane("Front"))
	doc.set_profile(id,"rectangle",[[0,0],[12.7,25.4]])
	check(await doc.extrude(id,76.2,"New"),"create exact physical reference solid")
	var mesh: ArrayMesh=Doc.mesh_from_faces(doc.bodies[0].faces)
	var export1:=Export.save(mesh,"test_",[blocked,folder.path_join("exports")])
	check(export1.error==OK and String(export1.path).get_base_dir()==folder.path_join("exports"),"unwritable preferred directory falls back successfully")
	check(FileAccess.get_file_as_string(blocked)=="keep this existing file","failed preferred export leaves existing files intact")
	var bytes:=FileAccess.get_file_as_bytes(export1.path)
	check(bytes.size()==84+bytes.decode_u32(80)*50 and bytes.decode_u32(80)*3==doc.bodies[0].faces.size(),"flushed STL has the complete expected binary geometry")
	var export2:=Export.save(mesh,"test_",[folder.path_join("exports")])
	check(export2.error==OK and export2.path!=export1.path and FileAccess.file_exists(export1.path),"rapid successive exports keep separate files")
	var failed:=Export.save(mesh,"test_",[blocked])
	check(failed.error!=OK and "failed" in Export.message(failed,true),"export failures produce actionable visible messages")
	SignalBus.export_finished.connect(func(ok,text):export_ok=ok;export_text=text)
	SignalBus.export_finished.emit(true,"STL saved in app exports")
	var menu=get_node("Viewport2Din3D/Viewport").get_child(0)
	check(menu.status_label.text=="STL saved in app exports" and wb.message=="STL saved in app exports","export status reaches both VR panels")
	# Real XRServer recenter API with a deterministic test interface.
	var previous=XRServer.primary_interface
	var xr:=TestXR.new()
	XRServer.add_interface(xr)
	XRServer.primary_interface=xr
	xr.camera_pose=Transform3D(Basis(Vector3.UP,0.5),Vector3(0.4,1.6,-0.2))
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT,true)
	var reference:=XRServer.get_reference_frame()
	check(not reference.is_equal_approx(Transform3D.IDENTITY),"test exercises a real non-identity recenter frame")
	wb.origin.global_transform=Transform3D(Basis(Vector3.UP,-0.3),Vector3(0.2,0.1,0.5))
	XRServer.world_scale=0.5
	var raw:=Transform3D(Basis(Vector3.UP,0.2),Vector3(0.3,0.9,-0.6))
	var expected: Transform3D=wb.origin.global_transform*reference*Transform3D(raw.basis,raw.origin*0.5)
	check(wb.stage_to_world(raw).is_equal_approx(expected),"table-to-world uses the same scale/recenter/origin order as tracked controllers")
	check(wb.world_to_stage(expected).is_equal_approx(raw),"physical contact conversion reverses recenter and world scale exactly")
	XRServer.world_scale=1.0
	XRServer.clear_reference_frame()
	wb.origin.global_transform=Transform3D.IDENTITY
	var model_plane:=Doc.unpack_transform(doc.sketch(id).plane)
	var stage_plane:=model_plane
	stage_plane.origin*=0.001
	doc.set_reference_plane({"plane_mm":Doc.pack_transform(model_plane),"stage_pose":Doc.pack_transform(stage_plane),"locked":true,"lock_rotation":true})
	var before: Dictionary=doc.snapshot()
	var part=doc.get_node("Part_"+str(doc.bodies[0].id))
	part._begin_move(part,null)
	var model_pose: Transform3D=part.model_transform
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT,true)
	wb._update_reference_view()
	var moved_display: Transform3D=doc.view_transform*model_pose
	part.global_transform=Transform3D(moved_display.basis.orthonormalized(),moved_display.origin)
	part._sync_pose()
	check(Doc.unpack_transform(doc.sketch(id).plane).is_equal_approx(Doc.unpack_transform(before.sketches[0].plane)),"recenter while holding preserves attached sketch plane")
	var error:=0.0
	for i in doc.bodies[0].faces.size():
		var a: Array=doc.bodies[0].faces[i]
		var b: Array=before.bodies[0].faces[i]
		error=maxf(error,Vector3(a[0],a[1],a[2]).distance_to(Vector3(b[0],b[1],b[2])))
	check(error<0.001,"recenter while holding never bakes room-frame movement into the solid")
	part._finish_move(part)
	XRServer.clear_reference_frame()
	wb._update_reference_view()
	check(not doc.busy and absf(Doc.volume(doc.bodies[0].faces)-25.4*50.8*76.2)<1,"release after recenter keeps metric dimensions and unlocks editing")
	XRServer.primary_interface=previous
	XRServer.remove_interface(xr)
	var conflict_id: int=doc.new_sketch(Transform3D.IDENTITY)
	doc.set_profile(conflict_id,"line",[[0,0],[10,0]],false)
	doc.add_inference(conflict_id,1,{"kind":"coincident","target":conflict_id,"index":0})
	# Invalid numeric values never close the keypad or alter geometry.
	wb.active_sketch=conflict_id
	wb.ui.edit_number("length")
	wb.ui.entry_text="-5"
	await wb.ui.apply_entry()
	check(wb.ui.keypad.visible and "positive" in wb.ui.entry.text,"numeric entry gives readable positive-dimension feedback")
	wb.ui.keypad.visible=false
	# Window handles use tracking space, independently of the document view.
	wb.enabled=true
	wb.open_panel()
	var panel_before_doc: Dictionary=doc.snapshot()
	var hand:=Node3D.new()
	add_child(hand)
	var panel_pose: Transform3D=wb.panel.global_transform
	hand.global_transform=Transform3D(panel_pose.basis.orthonormalized(),panel_pose*Vector3(0,-0.42,0.5))
	check(wb.panel_handles.hit(hand)=="move","laser can acquire the lower pill")
	wb.panel_handles.handle_input(hand,true,true)
	hand.global_position+=Vector3(0.2,0.1,0)
	wb.panel_handles.handle_input(hand,true,false)
	wb.panel_handles.handle_input(hand,false,false)
	check(wb.panel.global_position.distance_to(panel_pose.origin)>0.1,"pill drag moves only the window")
	var toward_eye: Vector3=(wb.camera.global_position-wb.panel.global_position).normalized()
	check(wb.panel.global_basis.z.normalized().dot(toward_eye)>0.995,"dragged window turns toward the viewer")
	var released: Transform3D=wb.panel.global_transform
	wb.camera.global_position+=Vector3(0.3,0,0)
	wb._update_panel_pose()
	check(wb.panel.global_transform.is_equal_approx(released),"released window keeps its orientation when the user looks/moves away")
	wb.camera.global_position-=Vector3(0.3,0,0)
	panel_pose=wb.panel.global_transform
	hand.global_transform=Transform3D(panel_pose.basis.orthonormalized(),panel_pose*Vector3(0.48,-0.40,0.5))
	check(wb.panel_handles.hit(hand)=="resize","laser can acquire the corner handle")
	wb.panel_handles.handle_input(hand,true,true)
	hand.global_position+=panel_pose.basis*Vector3(0.3,-0.25,0)
	wb.panel_handles.handle_input(hand,true,false)
	wb.panel_handles.handle_input(hand,false,false)
	check(wb.panel_handles.size_factor>1.1 and doc.snapshot()==panel_before_doc,"corner resize enlarges window without changing CAD dimensions or plane")
	var physical_pose: Transform3D=wb._panel_stage_pose
	var window_size: float=wb.panel_handles.size_factor
	XRServer.world_scale=8.43
	wb._update_panel_pose()
	check(wb.world_to_stage(wb.panel.global_transform).origin.distance_to(physical_pose.origin)<0.001 and is_equal_approx(wb.panel.global_basis.x.length()/8.43,window_size),"window physical position and size survive model view zoom")
	hand.global_transform=Transform3D(wb.panel.global_basis.orthonormalized(),wb.panel.global_transform*Vector3(0,0,0.5))
	doc.view_transform=Transform3D(Basis(Vector3.UP,0.8).scaled(Vector3.ONE*3),Vector3.ONE)
	check(wb._ray_hits_panel(hand),"UI ray detection is independent of model rotation and scale")
	for controller in [wb.left,wb.right]:
		var pointer=controller.get_node(str(controller.name)+"/FunctionPointer")
		check(pointer.enabled and pointer.show_laser==1 and pointer.show_target and pointer.suppress_mask==0,"both hands have visible menu lasers without enlarged suppression")
	for controller in [wb.left,wb.right]:
		var pointer=controller.get_node(str(controller.name)+"/FunctionPointer")
		pointer.scale=Vector3.ONE*8.43
		var end: Vector3=pointer.global_transform*Vector3(0,0,-1.5)
		pointer._visible_hit(end)
		check(is_equal_approx(pointer.get_node("Laser").mesh.size.z,1.5),"scaled laser ends at the actual menu hit")
		pointer.scale=Vector3.ONE
	XRServer.world_scale=1.0
	wb.close_panel()
	hand.queue_free()
	print("HEADSET RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
