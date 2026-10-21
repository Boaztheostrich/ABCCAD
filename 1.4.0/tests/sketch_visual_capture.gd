extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var wb: Node3D
var doc: Node3D
var view: Camera3D
func capture(name_: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String="res://tools/xr_agent/evidence/"+name_+".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SKETCH CAPTURE: "+path)
func _ready():
	super._ready()
	await get_tree().process_frame
	get_viewport().use_xr=false
	world_environment.environment.background_mode=Environment.BG_COLOR
	world_environment.environment.background_color=Color("f2f5f8")
	view=Camera3D.new(); add_child(view); view.current=true
	view.projection=Camera3D.PROJECTION_ORTHOGONAL
	view.size=0.32
	view.global_position=Vector3(0,1.15,-0.25)
	for hand in [get_node("XROrigin3D/LeftHand/LeftHand"),get_node("XROrigin3D/RightHand/RightHand")]: hand.visible=false
	if has_node("Test Cube"): get_node("Test Cube").visible=false
	wb=get_node("AdvancedCAD"); doc=wb.document
	wb.enabled=true
	wb.camera.global_transform=view.global_transform
	wb.open_panel(); wb.set_process(false)
	wb.panel.global_position=Vector3(-2,1.15,-0.6)
	wb.begin_sketch()
	view.global_position=Vector3(0.25,1.35,-0.3)
	view.look_at(doc.origin_mm*0.001)
	await capture("cad-sketch-planes")
	view.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.175,-0.25))
	view.size=0.22
	doc.origin_mm=Vector3(-30,1150,-650)
	wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	doc.set_profile(id,"line",[[0,0],[60,0]],false)
	doc.add_inference(id,0,{"kind":"origin"})
	doc.add_inference(id,1,{"kind":"horizontal"})
	await doc.dimension(id,"length:1",60)
	wb.tool="line"; wb._redraw()
	wb.sketch_visual.update_preview(doc.sketch(id),Vector2(60,50),true)
	await capture("cad-sketch-line-preview")
	doc.set_profile(id,"line",[[0,0],[60,0],[60,50]],true)
	doc.add_inference(id,2,{"kind":"vertical"})
	wb.tool="select"
	wb._redraw()
	await capture("cad-sketch-underdefined")
	await doc.dimension(id,"length:0",80.131)
	wb._redraw()
	await capture("cad-sketch-defined")
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1,"origin_mm":[0,1150,-650]})
	view.global_position.y=1.15
	wb.new_base_sketch("Front"); id=wb.active_sketch
	doc.set_profile(id,"circle",[[0,0],[36.4725,0]],true)
	doc.add_inference(id,0,{"kind":"origin"})
	wb.tool="select"; wb._redraw()
	await capture("cad-sketch-circle-underdefined")
	var circle_view:=view.global_transform
	for side in [-1,1]:
		view.global_position=Vector3(side*0.22,1.15,-0.38)
		view.look_at(Vector3(0,1.15,-0.65))
		await capture("cad-sketch-text-left" if side<0 else "cad-sketch-text-right")
	view.global_transform=circle_view
	await doc.dimension(id,"diameter",83.892)
	wb._redraw()
	await capture("cad-sketch-circle-defined")
	wb.ui.show_command("extrude")
	wb.depth_mm=30
	wb.extrude_arrow.refresh()
	view.global_position=Vector3(0.10,1.24,-0.40)
	view.look_at(Vector3(0,1.15,-0.63))
	wb.extrude_preview.refresh(0.2)
	await capture("cad-extrude-direction-positive")
	wb.reverse_extrude_direction()
	wb.extrude_preview.refresh(0.2)
	await capture("cad-extrude-direction-negative")
	wb.depth_mm=10
	wb.ui.show_command("select")
	await wb.extrude()
	var plane: Transform3D=Doc.unpack_transform(doc.sketch(id).plane)
	wb.select_face((plane*Vector3(0,0,11))*0.001,-plane.basis.z)
	view.global_position=Vector3(0.10,1.22,-0.40)
	view.look_at(plane.origin*0.001+Vector3(0,0,0.005))
	await capture("cad-face-selected")
	wb.panel.global_position=Vector3(0,1.15,-0.65)
	wb.panel.global_basis=Basis.IDENTITY
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-studio-eye-controls.png")
	wb.ui.request_delete_sketch(id)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-delete-confirmation.png")
	wb.ui.cancel_confirmation()
	wb.ui.request_clear_all()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-clear-confirmation.png")
	wb.ui.cancel_confirmation()
	var body_id: int=doc.bodies[0].id
	plane.origin+=plane.basis.z*10
	id=doc.new_sketch(plane,body_id); doc.set_profile(id,"circle",[[0,0],[12,0]],true)
	wb.active_sketch=id; wb.selected_body=body_id; wb.operation="Remove"; wb.depth_mm=-10
	wb.panel.global_position=Vector3(-2,1.15,-0.6)
	wb.ui.show_command("extrude"); wb.extrude_arrow.refresh(); wb.extrude_preview.refresh(0.2)
	for _i in 4: await get_tree().process_frame
	await capture("cad-extrude-remove-preview")
	wb.ui.show_command("sketch"); wb.extrude_preview.cancel()
	wb.plane_visibility["Sketch plane"]=true; wb.sketch_visibility[wb.active_sketch]=true
	wb._redraw()
	await capture("cad-face-highlight-coplanar")
	wb.selected_hit={}; wb._redraw()
	await capture("cad-coplanar-plane-front")
	view.global_position=Vector3(-0.12,1.22,-0.9); view.look_at(Vector3(0,1.15,-0.64))
	await capture("cad-coplanar-plane-back")
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1,"origin_mm":[-30,1150,-650]})
	view.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.18,-0.25));view.size=0.22
	wb.sketch_visibility.clear()
	wb.new_base_sketch("Front");id=wb.active_sketch
	doc.set_profile(id,"line",[[0,0],[60,0],[60,60]],false)
	wb.tool="line"; wb._redraw()
	var aligned: Dictionary=doc.infer_point(id,Vector2(3,62),30)
	wb.sketch_visual.update_preview(doc.sketch(id),aligned.point,true)
	wb.sketch_visual.update_guides(aligned.guides,Doc.unpack_transform(doc.sketch(id).plane))
	await capture("cad-sketch-alignment-guide")
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-sketch-reuse-controls.png")
	get_tree().quit()
