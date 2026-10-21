extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1; push_error("SELECTION FAIL: "+text_)
	else: print("SELECTION PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	wb.enabled=true; wb.open_panel()
	wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	var before: Dictionary=doc.snapshot()
	wb.toggle_plane_visibility("Front")
	var hand:=Node3D.new(); add_child(hand)
	hand.global_position=Vector3(0,1.15,0)
	check(wb.pick_base_plane(hand)!="Front" and doc.snapshot()==before,"hidden base plane is not selectable and never edits model")
	wb.toggle_plane_visibility("Front")
	check(wb.pick_base_plane(hand)=="Front","show restores base-plane selection")
	doc.set_profile(id,"circle",[[0,0],[20,0]])
	wb._redraw()
	before=doc.snapshot()
	wb.toggle_sketch_visibility(id)
	check(wb.sketch_visual.dimensions.is_empty() and doc.snapshot()==before,"eye hides sketch lines/dimensions without changing document")
	wb.toggle_sketch_visibility(id)
	check(wb.sketch_visual.dimensions.size()==1,"eye restores the sketch and diameter")
	check(await wb.extrude(),"create selectable disc")
	check(not wb.sketch_visibility[id] and not wb.plane_visibility["Sketch plane"],"extrusion hides consumed sketch and its display plane")
	var plane: Transform3D=Doc.unpack_transform(doc.sketch(id).plane)
	wb.select_face((plane*Vector3(0,0,11))*0.001,-plane.basis.z)
	check(not wb.selected_hit.is_empty() and wb.face_highlight.mesh!=null,"selected disc face receives orange highlight")
	check(wb.face_highlight.mesh.get_faces().size()>3,"highlight covers complete triangulated face")
	check(wb.face_highlight.material_override.albedo_color.r>0.9 and wb.face_highlight.visible,"selected face highlight is visibly orange")
	wb.select_face(Vector3(100,100,100),Vector3.UP)
	check(wb.selected_hit.is_empty() and wb.selected_body==-1 and wb.face_highlight.mesh==null,"empty-space click clears face, body and highlight")
	var bid: int=doc.bodies[0].id
	var cut: int=doc.new_sketch(plane,bid)
	doc.set_profile(cut,"circle",[[0,0],[5,0]])
	check(await doc.extrude(cut,10,"Remove"),"prepare annular face")
	wb.select_face((plane*Vector3(10,0,11))*0.001,-plane.basis.z)
	var vertices: PackedVector3Array=wb.face_highlight.mesh.get_faces()
	var center_clear:=true
	for i in range(0,vertices.size(),3):
		if Geometry3D.ray_intersects_triangle(plane*Vector3(0,0,11),-plane.basis.z,vertices[i]*1000,vertices[i+1]*1000,vertices[i+2]*1000)!=null: center_clear=false
	check(center_clear and vertices.size()>3,"face highlight preserves the real hole and never draws a fake cap")
	wb.select_face((plane*Vector3(0,0,11))*0.001,-plane.basis.z)
	check(wb.selected_hit.is_empty() and not wb.face_highlight.visible,"clicking through empty hole deselects")
	check(Doc.validate(doc.snapshot()).is_empty(),"selection and visibility preserve saved CAD data")
	print("SELECTION VISIBILITY RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
