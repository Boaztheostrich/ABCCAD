extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
func capture(name_: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/xr_agent/evidence/"+name_+".png")
	print("PROJECT CAPTURE: "+name_)
func _ready():
	super._ready()
	await get_tree().process_frame
	get_viewport().use_xr=false
	world_environment.environment.background_mode=Environment.BG_COLOR
	world_environment.environment.background_color=Color("f2f5f8")
	var view:=Camera3D.new();add_child(view);view.current=true
	view.projection=Camera3D.PROJECTION_ORTHOGONAL;view.size=0.14
	view.global_position=Vector3(0,1.15,-0.3)
	for hand in [get_node("XROrigin3D/LeftHand/LeftHand"),get_node("XROrigin3D/RightHand/RightHand")]:hand.visible=false
	if has_node("Test Cube"):get_node("Test Cube").visible=false
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.camera.global_transform=view.global_transform
	wb.open_panel();wb.set_process(false);wb.panel.global_position=Vector3(-2,1.15,-0.6)
	wb.new_base_sketch("Front");var source: int=wb.active_sketch
	doc.set_profile(source,"rectangle",[[0,0],[20,20]],true);await wb.extrude()
	var plane:=Doc.unpack_transform(doc.sketch(source).plane)
	wb.select_face((plane*Vector3(0,0,11))*0.001,-plane.basis.z);wb.new_sketch(true)
	var id: int=wb.active_sketch;var face:=Doc.unpack_transform(doc.sketch(id).plane)
	view.global_position=Vector3(face.origin.x*0.001,face.origin.y*0.001,-0.3)
	wb.selected_hit={};wb._redraw();wb.ui.show_command("sketch");wb.start_use_edge()
	var ray:=Node3D.new();add_child(ray)
	ray.global_transform=Transform3D(face.basis,(face*Vector3(20,0,50))*0.001)
	var hit: Dictionary=wb.edge_hit(ray)
	wb.sketch_visual.update_project_highlight([hit.points],face)
	await capture("cad-project-edge-hover")
	for aim in [Vector2(0,-20),Vector2(0,20)]:
		ray.global_transform=Transform3D(face.basis,(face*Vector3(aim.x,aim.y,50))*0.001)
		wb.use_edge(wb.edge_hit(ray))
	await capture("cad-project-two-independent-edges")
	for aim in [Vector2(-20,0),Vector2(20,0)]:
		ray.global_transform=Transform3D(face.basis,(face*Vector3(aim.x,aim.y,50))*0.001)
		wb.use_edge(wb.edge_hit(ray))
	ray.global_transform=Transform3D(face.basis,(face*Vector3(20,0,50))*0.001)
	hit=wb.edge_hit(ray);wb.sketch_visual.update_project_highlight([hit.points],face)
	await capture("cad-project-four-edge-region")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/cad-project-ui.png")
	get_tree().quit()
