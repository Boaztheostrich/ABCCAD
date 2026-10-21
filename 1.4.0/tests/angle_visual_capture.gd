extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
const Angle=preload("res://cad/CADAngleDimension.gd")
func capture(name_: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/xr_agent/evidence/"+name_+".png")
func _ready():
	super._ready()
	await get_tree().process_frame
	get_viewport().use_xr=false
	world_environment.environment.background_mode=Environment.BG_COLOR
	world_environment.environment.background_color=Color("f2f5f8")
	var view:=Camera3D.new();add_child(view);view.current=true
	view.projection=Camera3D.PROJECTION_ORTHOGONAL;view.size=0.15
	view.global_position=Vector3(0.02,1.18,-0.3)
	for hand in [get_node("XROrigin3D/LeftHand/LeftHand"),get_node("XROrigin3D/RightHand/RightHand")]:hand.visible=false
	if has_node("Test Cube"):get_node("Test Cube").visible=false
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.camera.global_transform=view.global_transform
	wb.open_panel();wb.set_process(false);wb.panel.global_position=Vector3(-2,1.15,-0.6)
	wb.new_base_sketch("Front");var id: int=wb.active_sketch
	doc.set_profile(id,"line",[[0,0],[0,70],[50,20]],false)
	var s: Dictionary=doc.sketch(id)
	doc.add_angle(id,Angle.placed(s,Angle.pair(s,0,1),Vector2(22,18)))
	await capture("cad-angle-inside")
	doc.add_angle(id,Angle.placed(s,Angle.pair(s,0,1),Vector2(-35,50)))
	await capture("cad-angle-outside")
	wb.start_angle();wb.angle_click(Vector2(0,30));wb.angle_click(Vector2(25,45))
	wb.sketch_visual.update_angle(s,Angle.placed(s,wb.angle_pending,Vector2(12,40)),[[s.points[0],s.points[1]],[s.points[1],s.points[2]]])
	await capture("cad-angle-placement")
	wb.ui.show_command("sketch")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-angle-ui.png")
	wb.end_sketch_tool();doc.clear_all()
	wb.new_base_sketch("Front");id=wb.active_sketch
	doc.set_profile(id,"circle",[[35,25],[60,25]],true);await doc.extrude(id,12,"New")
	var source: Dictionary=doc.sketch(id)
	var plane:=Doc.unpack_transform(source.plane)
	var body: Dictionary=doc.bodies[-1]
	wb.selected_hit={"normal":plane.basis.z,"point_mm":plane*Vector3(40,30,12),"source":{"id":body.id,"faces":body.faces}}
	wb.selected_body=body.id;wb.new_sketch(true);id=wb.active_sketch
	var face:=Doc.unpack_transform(doc.sketch(id).plane)
	view.global_position=face.origin*0.001+Vector3(0,0,0.35)
	var edges: Array=[]
	for i in 96:edges.append([Vector2.from_angle(TAU*i/96)*25,Vector2.from_angle(TAU*(i+1)/96)*25])
	doc.add_projected_edges(id,edges)
	wb.selected_hit={};wb._redraw()
	await capture("cad-centered-face-circle-center")
	get_tree().quit()
