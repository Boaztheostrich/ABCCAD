extends "res://main.gd"
var checks:=0
var failures:=0
var wb: Node3D
var tracker: XRPositionalTracker
func check(ok: bool,text_: String):
	checks+=1
	if ok: print("FLOATING PASS: "+text_)
	else: failures+=1; push_error("FLOATING FAIL: "+text_)
func frames():
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
func button(text_: String) -> Button:
	for control in wb.ui.keypad.find_children("*","Button",true,false):
		if control.text==text_: return control
	return null
func aim_at(at: Vector3,basis_: Basis):
	var pointer: Node3D=wb._ray_node(wb.right)
	var offset: Transform3D=wb.right.global_transform.affine_inverse()*pointer.global_transform
	var desired:=Transform3D(basis_,at+basis_.z*0.4)
	var pose: Transform3D=wb.origin.global_transform.affine_inverse()*desired*offset.affine_inverse()
	tracker.set_pose("default",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func tap(text_: String):
	var target:=button(text_)
	var pixel: Vector2=target.get_global_rect().get_center()
	var panel: Node3D=wb.number_pad.panel
	var local:=Vector3((pixel.x/560.0-0.5)*0.32,(0.5-pixel.y/770.0)*0.44,0)
	aim_at(panel.global_transform*local,panel.global_basis.orthonormalized())
	await frames()
	tracker.set_input("trigger_click",true); await frames()
	tracker.set_input("trigger_click",false); await frames()
func _ready():
	super._ready()
	get_node("/root/DriveUpload").endpoint=""
	await frames()
	wb=get_node("AdvancedCAD")
	wb.enabled=true;wb.open_panel()
	wb.camera.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.4,0.2))
	wb.panel.global_position=Vector3(-1.0,1.3,-0.8);wb._remember_panel_pose()
	wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	wb.document.set_profile(id,"rectangle",[[0,0],[20,10]],true)
	wb.ui.show_command("sketch")
	tracker=XRPositionalTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name="right_hand"
	tracker.set_input("trigger_click",false);tracker.set_input("by_button",false);tracker.set_input("grip",0.0);tracker.set_input("primary",Vector2.ZERO)
	tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0.2,1.3,-0.2)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker);await frames()
	var before: Dictionary=wb.document.snapshot()
	var studio_pose: Transform3D=wb.panel.global_transform
	wb.ui.edit_number("width",Vector3(0,1.3,-0.6));await frames()
	var pad: Node3D=wb.number_pad.panel
	check(pad.visible and wb.panel.visible and not wb.ui.is_ancestor_of(wb.ui.keypad),"numeric entry opens in its own viewport while Part Studio stays visible")
	check(pad.screen_size.x<wb.panel.screen_size.x/2 and pad.screen_size.y<wb.panel.screen_size.y,"number window is physically smaller than Part Studio")
	check(pad.global_position.distance_to(wb.camera.global_position)<1.0,"number window opens within comfortable view distance")
	var bounds:=Rect2(Vector2.ZERO,Vector2(560,770))
	check(wb.ui.keypad.find_children("*","Button",true,false).all(func(b):return bounds.encloses(b.get_global_rect())),"all number and action buttons fit inside the floating viewport")
	await tap("6");await tap("0")
	check(wb.ui.entry_text=="60","native controller pointer enters digits in floating keypad")
	await tap("Apply")
	check(not pad.visible and not wb.ui.keypad.visible and is_equal_approx(wb.ui._value("width"),60),"native Apply drives sketch dimension and closes floating window")
	wb.document.undo();check(wb.document.snapshot()==before,"Undo restores geometry after floating dimension edit")
	wb.ui.edit_number("width");await frames()
	await tap("0");await tap("Apply")
	check(pad.visible and wb.document.snapshot()==before,"invalid zero dimension keeps window open and geometry intact")
	await tap("Cancel")
	check(not pad.visible and wb.document.snapshot()==before,"native Cancel dismisses without changing geometry")
	wb.ui.edit_number("height");await frames()
	var initial: Transform3D=pad.global_transform
	var title: Vector3=pad.global_transform*Vector3(0,0.20,0)
	aim_at(title,pad.global_basis.orthonormalized());await frames()
	tracker.set_input("trigger_click",true);await frames()
	check(wb.number_pad.active_hand==wb._ray_node(wb.right),"native trigger on header captures floating window drag")
	var pose: Transform3D=tracker.get_pose("default").transform
	pose.origin+=Vector3(0.16,0.06,-0.03)
	tracker.set_pose("default",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await frames()
	check(pad.global_position.distance_to(initial.origin)>0.1 and wb.document.snapshot()==before and wb.panel.global_transform.is_equal_approx(studio_pose),"drag moves only numeric window and keeps CAD and Part Studio fixed")
	tracker.set_input("trigger_click",false);await frames()
	var released: Transform3D=pad.global_transform
	pose.origin+=Vector3(0.1,0,0);tracker.set_pose("default",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await frames()
	check(wb.number_pad.active_hand==null and pad.global_transform.is_equal_approx(released),"release leaves numeric window stationary")
	tracker.set_input("by_button",true);await frames();tracker.set_input("by_button",false);await frames()
	check(not pad.visible,"controller B cancels floating editor")
	wb.ui.edit_number("width");wb.close_panel();await frames()
	check(not pad.visible and wb.number_pad.active_hand==null,"closing Part Studio also closes floating editor")
	wb.open_panel();wb.ui.show_command("extrude");wb.depth_mm=10;wb.extrude_arrow.refresh();await frames()
	var arrow: Node3D=wb.extrude_arrow
	check(arrow.visible and arrow.label.modulate==Color.WHITE and arrow.label.font_size*arrow.label.pixel_size<0.01 and arrow.label_hit_size.x<0.10 and arrow.label_hit_size.y<0.03 and arrow.label.outline_modulate==Color.BLACK and arrow.get_child_count()==3,"extrusion depth is compact white text with a black stroke and no backing mesh")
	var saved_camera: Transform3D=wb.camera.global_transform
	var saved_depth: float=wb.depth_mm
	var geometry_before: Dictionary=wb.document.snapshot()
	var gap_ray:=Node3D.new();add_child(gap_ray)
	for yaw in [-1.0,0.0,1.0]:
		wb.camera.global_basis=Basis(Vector3.UP,yaw)
		arrow.refresh()
		var screen_right: Vector3=wb.camera.global_basis.x.normalized()
		var separation: float=absf((arrow.label.global_position-arrow.tip_point).dot(screen_right))
		check(separation>arrow.label_hit_size.x*XRServer.world_scale/2+0.015,"readout stays beside arrow after viewer turns, with depth unchanged")
		gap_ray.global_transform=Transform3D(wb.camera.global_basis,arrow.tip_point+wb.camera.global_basis.z*0.4)
		check(arrow.hit(gap_ray) and not arrow.label_hit(gap_ray),"arrow drag target is exposed and separate from numeric label")
	wb.depth_mm=-100000.0;arrow.refresh()
	check(arrow.label_hit_size.x>=ThemeDB.fallback_font.get_string_size(arrow.label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,arrow.label.font_size).x*arrow.label.pixel_size,"long signed depth fits inside numeric-entry hit bounds")
	wb.depth_mm=saved_depth;wb.camera.global_transform=saved_camera;arrow.refresh();gap_ray.queue_free()
	check(wb.document.snapshot()==geometry_before,"compact readout and viewer movement do not change CAD geometry")
	var ray:=Node3D.new();add_child(ray)
	ray.global_transform=Transform3D(wb.camera.global_basis,arrow.label.global_position+wb.camera.global_basis.z*0.4)
	check(arrow.label_hit(ray),"readable extrusion label has a numeric-entry hit target")
	check(wb.pointer_surface_hit(ray).get("depth_label",false),"laser cursor stops on the selectable extrusion readout")
	wb._world_click(ray);await frames()
	check(pad.visible and wb.ui.entry_field=="depth","selecting extrusion readout opens floating depth editor")
	await tap("2");await tap("5");await tap("Apply")
	check(is_equal_approx(wb.depth_mm,25) and not pad.visible,"floating numeric entry updates extrusion depth")
	wb.ui.edit_number("depth");await frames()
	await tap("±");await tap("1");await tap("5");await tap("Apply")
	check(is_equal_approx(wb.depth_mm,-15) and not pad.visible,"floating editor supports signed extrusion depths")
	if "--preview" in OS.get_cmdline_user_args():
		wb.ui.edit_number("depth");await frames()
		await RenderingServer.frame_post_draw
		pad.get_node("Viewport").get_texture().get_image().save_png("/private/tmp/abccad-floating-keypad.png")
		wb.ui.keypad.visible=false
		var camera:=Camera3D.new();add_child(camera)
		camera.global_transform=Transform3D(Basis.IDENTITY,arrow.label.global_position+Vector3(0,0,0.65));camera.current=true
		await frames();await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/private/tmp/abccad-extrusion-readout.png")
	XRServer.remove_tracker(tracker);ray.queue_free()
	print("FLOATING RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
