extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
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
	view.projection=Camera3D.PROJECTION_ORTHOGONAL;view.size=0.28
	for hand in [get_node("XROrigin3D/LeftHand/LeftHand"),get_node("XROrigin3D/RightHand/RightHand")]:hand.visible=false
	if has_node("Test Cube"):get_node("Test Cube").visible=false
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.panel.global_position=Vector3(-2,1.15,-0.6)
	var plane:=Transform3D(Basis.from_euler(Vector3(0.17,0.31,0.13)),Vector3(1223.465,1156.737,-675.231))
	var id: int=doc.new_sketch(plane)
	doc.set_profile(id,"rectangle",[[0,0],[100,100]],true);await doc.extrude(id,10,"New")
	var bid: int=doc.bodies[0].id
	var cut: int=doc.new_sketch(plane,bid)
	doc.set_profile(cut,"circle",[[0,0],[35,0]],true);await doc.extrude(cut,10,"Remove")
	wb.select_face((plane*Vector3(-60,-60,60))*0.001,-plane.basis.z)
	var face: Transform3D=wb.face_sketch_plane(wb.selected_hit)
	wb.new_sketch(true);cut=wb.active_sketch
	var at: Vector3=face.affine_inverse()*(plane*Vector3(-60,-60,10))
	doc.set_profile(cut,"circle",[[at.x,at.y],[at.x+8,at.y]],true);await doc.extrude(cut,-54,"Remove")
	wb.selected_hit={};wb.plane_visibility["Sketch plane"]=false
	for s in doc.sketches:wb.sketch_visibility[int(s.id)]=false
	wb._redraw()
	for side in [1,-1]:
		var center: Vector3=plane*Vector3(0,0,5)*0.001
		view.global_position=center+plane.basis.z*0.4*side+plane.basis.x*0.08
		view.look_at(center,plane.basis.y)
		await capture("cad-face-cut-front" if side==1 else "cad-face-cut-back")
	get_tree().quit()
