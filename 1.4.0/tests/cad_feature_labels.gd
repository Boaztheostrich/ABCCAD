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
const Doc=preload("res://cad/CADDocument.gd")
func _ready():
	# Use the production scene and pointer helpers, with a separate suite body.
	super._ready()
	get_node("/root/DriveUpload").endpoint=""
	await frames()
	wb=get_node("AdvancedCAD");wb.enabled=true;wb.open_panel()
	wb.camera.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.4,0.2))
	wb.panel.global_position=Vector3(-1.0,1.3,-0.8);wb._remember_panel_pose()
	var doc=wb.document
	wb.new_base_sketch("Front")
	var root: int=wb.active_sketch
	doc.set_profile(root,"rectangle",[[0,0],[20,15]],true)
	check(await doc.extrude(root,10,"New"),"create first feature")
	var bid: int=doc.bodies[0].id
	var cut: int=doc.new_sketch(Doc.unpack_transform(doc.sketch(root).plane),bid)
	doc.set_profile(cut,"circle",[[0,0],[5,0]],true)
	check(await doc.extrude(cut,5,"Remove",bid),"create downstream blind cut")
	wb.active_sketch=root;wb._changed()
	var rows: Array=[]
	for child in wb.ui.tree.get_children():
		if child is HBoxContainer: rows.append(child.get_child(0).text)
	check(rows[4].begins_with("Sketch") and rows[5].begins_with("↳ Extrude") and rows[6].begins_with("Sketch") and rows[7].begins_with("↳ Extrude"),"each sketch is immediately followed by its extrusion")
	if "--preview" in OS.get_cmdline_user_args():
		await frames();await RenderingServer.frame_post_draw
		wb.panel.get_node("Viewport").get_texture().get_image().save_png("/private/tmp/abccad-feature-list.png")
	var before: Dictionary=doc.snapshot()
	var volume: float=Doc.volume(doc.body(bid).faces)
	wb.ui.edit_feature(bid,0)
	check(wb.ui.keypad.visible and float(wb.ui.entry_text)==10 and wb.ui.entry_body==bid,"feature click opens its existing depth immediately")
	wb.ui.entry_text="20";await wb.ui.apply_entry()
	check(doc.bodies.size()==1 and doc.body(bid).features.size()==2 and doc.body(bid).features[0].depth_mm==20,"depth edit changes original feature without creating another part or feature")
	check(absf(Doc.volume(doc.body(bid).faces)-volume-12000)<0.1,"depth edit replays downstream Remove with expected volume")
	doc.undo();check(doc.snapshot()==before,"one Undo restores feature depth and cached faces")
	doc.redo();check(doc.body(bid).features[0].depth_mm==20,"Redo restores edited extrusion")
	var good: Dictionary=doc.snapshot();var history: Array=doc.undo_steps.duplicate(true)
	check(not await doc.edit_feature_depth(bid,0,-10),"reject depth that makes downstream cut invalid")
	check(doc.snapshot()==good and doc.undo_steps==history,"failed feature edit preserves solid and undo stack")
	check(not await doc.edit_feature_depth(bid,8,20) and not await doc.edit_feature_depth(bid,0,0),"invalid feature index and zero depth are rejected")
	wb.ui.edit_feature(bid,0)
	doc.undo()
	var stale: Dictionary=doc.snapshot()
	wb.ui.entry_text="3";await wb.ui.apply_entry()
	check(doc.snapshot()==stale and wb.ui.keypad.visible,"stale editor cannot modify a feature after history changes")
	wb.ui.keypad.visible=false
	doc.clear_all();wb.new_base_sketch("Front");root=wb.active_sketch
	doc.set_profile(root,"circle",[[0,0],[30,0]],true)
	var inner: int=doc.new_entity(root,"circle")
	doc.set_profile(inner,"circle",[[0,0],[32,0]],true)
	wb.active_sketch=root;wb.tool="select";wb.ui.show_command("sketch");wb._changed()
	var visual=wb.sketch_visual
	check(visual.dimensions.size()==2,"concentric circles expose two labels")
	var d: Dictionary=visual.dimensions[0];var other: Dictionary=visual.dimensions[1]
	check(not visual._label_bounds(d,d.point).intersects(visual._label_bounds(other,other.point)),"nearby concentric diameter labels do not overlap")
	var geometry: Dictionary=doc.snapshot()
	var ray:=Node3D.new();add_child(ray)
	ray.global_transform=Transform3D(Basis.IDENTITY,d.node.global_position+Vector3(0,0,0.4))
	check(visual.hit_dimension(ray).get("sketch")==root and wb.pointer_surface_hit(ray).get("dimension_label",false),"visible label and laser cursor use the same hit target")
	check(wb.dimension_drag.begin(ray),"trigger captures label")
	ray.global_position+=Vector3(0.04,0.025,0);wb.dimension_drag.update()
	check(wb.dimension_drag.moved and not wb.ui.keypad.visible and doc.snapshot()==geometry,"held drag previews label movement without changing model")
	var moved: Vector2=d.point
	wb.dimension_drag.end()
	check(doc.sketch(root).has("dimension_labels") and visual.dimensions[0].point.distance_to(moved)<0.001,"release persists label placement")
	check(doc.sketch(root).points==geometry.sketches[0].points and doc.sketch(root).constraints==geometry.sketches[0].constraints,"label drag leaves dimensions and constraints untouched")
	var placed: Dictionary=doc.snapshot()
	check(Doc.validate(JSON.parse_string(JSON.stringify(placed))).is_empty(),"save schema accepts persisted label offsets")
	doc.undo();check(doc.snapshot()==geometry,"one Undo restores automatic label placement")
	doc.redo();check(doc.sketch(root).has("dimension_labels"),"Redo restores dragged label")
	doc.load_document(JSON.parse_string(JSON.stringify(placed)))
	check(visual.dimensions[0].point.distance_to(moved)<0.001,"label placement survives JSON save/load")
	placed=doc.snapshot()
	d=visual.dimensions[0]
	ray.global_transform=Transform3D(Basis.IDENTITY,d.node.global_position+Vector3(0,0,0.4))
	check(wb.dimension_drag.begin(ray),"moved label is selectable at new location")
	ray.global_position+=Vector3(-0.02,0.01,0);wb.dimension_drag.update();wb.dimension_drag.end(true)
	check(doc.snapshot()==placed,"cancelled drag retains last saved placement")
	d=visual.dimensions[0];ray.global_transform=Transform3D(Basis.IDENTITY,d.node.global_position+Vector3(0,0,0.4))
	wb.dimension_drag.begin(ray);wb.dimension_drag.end()
	check(wb.ui.keypad.visible and wb.ui.entry_field=="diameter" and wb.ui.entry_sketch==root,"short click still opens dimension editor")
	wb.ui.keypad.visible=false
	# Exercise real XR press/hold/release rather than only the drag methods.
	tracker=XRPositionalTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name="right_hand"
	tracker.set_input("trigger_click",false);tracker.set_input("by_button",false);tracker.set_input("grip",0.0);tracker.set_input("primary",Vector2.ZERO)
	tracker.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker);await frames()
	d=visual.dimensions[0];aim_at(d.node.global_position,Basis.IDENTITY);await frames()
	tracker.set_input("trigger_click",true);await frames()
	check(wb.dimension_drag.hand==wb._ray_node(wb.right),"native trigger starts label capture")
	var pose: Transform3D=tracker.get_pose("default").transform
	pose.origin+=Vector3(0.025,0.015,0);tracker.set_pose("default",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await frames()
	check(wb.dimension_drag.moved and not wb.ui.keypad.visible,"native hold moves label without opening numeric window")
	tracker.set_input("trigger_click",false);await frames()
	check(wb.dimension_drag.hand==null and not wb.ui.keypad.visible,"native release commits label drag")
	d=visual.dimensions[0];aim_at(d.node.global_position,Basis.IDENTITY);await frames()
	tracker.set_input("trigger_click",true);await frames();tracker.set_input("trigger_click",false);await frames()
	check(wb.ui.keypad.visible,"native short trigger click opens numeric editor")
	wb.ui.keypad.visible=false
	if "--preview" in OS.get_cmdline_user_args():
		await frames();await RenderingServer.frame_post_draw
		var camera:=Camera3D.new();add_child(camera)
		camera.global_transform=Transform3D(Basis.IDENTITY,visual.dimensions[0].node.global_position+Vector3(-0.035,0.02,0.24));camera.current=true
		await frames();await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/private/tmp/abccad-label-spacing.png")
	XRServer.remove_tracker(tracker);ray.queue_free()
	print("FEATURE LABELS RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
