extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
func capture(name_: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/xr_agent/evidence/"+name_+".png")
func panel_capture(name_: String,wb):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	wb.panel.get_node("Viewport").get_texture().get_image().save_png("res://tools/xr_agent/evidence/"+name_+".png")
func _ready():
	super._ready()
	await get_tree().process_frame
	get_viewport().use_xr=false
	world_environment.environment.background_mode=Environment.BG_COLOR
	world_environment.environment.background_color=Color("e9eef4")
	var view:=Camera3D.new();add_child(view);view.current=true
	view.projection=Camera3D.PROJECTION_ORTHOGONAL;view.size=0.20
	view.global_position=Vector3(0,1.15,-0.3)
	for hand in [get_node("XROrigin3D/LeftHand/LeftHand"),get_node("XROrigin3D/RightHand/RightHand")]:hand.visible=false
	if has_node("Test Cube"):get_node("Test Cube").visible=false
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.camera.global_transform=view.global_transform
	wb.open_panel();wb.set_process(false);wb.panel.global_position=Vector3(-2,1.15,-0.6)
	wb.new_base_sketch("Front");var root: int=wb.active_sketch
	doc.set_profile(root,"rectangle",[[0,0],[55,40]],true)
	var circle: int=doc.new_entity(root,"circle");doc.set_profile(circle,"circle",[[-25,0],[-13,0]],true)
	circle=doc.new_entity(root,"circle");doc.set_profile(circle,"circle",[[25,0],[37,0]],true)
	var line: int=doc.new_entity(root,"line");doc.set_profile(line,"line",[[0,-40],[0,40]],false)
	wb.active_sketch=line;wb.ui.show_command("sketch");wb._changed()
	await capture("cad-multi-one-sketch")
	await panel_capture("cad-multi-sketch-ui",wb)
	wb.ui.show_command("extrude")
	await panel_capture("cad-multi-select-prompt",wb)
	wb.select_region(Vector2(-25,0));wb.select_region(Vector2(40,0))
	await capture("cad-multi-orange-areas")
	await panel_capture("cad-multi-selected-ui",wb)
	wb.depth_mm=10;wb.extrude_arrow.refresh();wb.extrude_preview.refresh(0)
	await capture("cad-multi-depth-preview")
	await wb.extrude();wb.ui.show_command("select");wb.extrude_preview.refresh(0)
	var plane:=Doc.unpack_transform(doc.sketch(root).plane)
	var center: Vector3=plane*Vector3(0,0,5)*0.001
	view.global_position=center+Vector3(0.10,0.08,0.26);view.look_at(center)
	await capture("cad-multi-solid-result")
	get_tree().quit()
