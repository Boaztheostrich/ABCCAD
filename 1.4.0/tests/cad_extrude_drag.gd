extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1; push_error("EXTRUDE DRAG FAIL: "+text_)
	else: print("EXTRUDE DRAG PASS: "+text_)
func frames():
	for i in 4: await get_tree().process_frame
func _ready():
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	doc.set_profile(id,"rectangle",[[0,0],[20,15]],true)
	wb.ui.show_command("extrude");wb.depth_mm=10;wb.extrude_arrow.refresh()
	var before: Dictionary=doc.snapshot()
	var hand:=Node3D.new();add_child(hand)
	for scale_ in [0.2,1.0,8.43]:
		doc.view_transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_),Vector3.ZERO)
		for sign_ in [-1,1]:
			wb.depth_mm=sign_*10.0;wb.extrude_arrow.refresh()
			var arrow=wb.extrude_arrow
			hand.global_position=arrow.tip_point+Vector3(0,0,0.2)
			hand.global_basis=Basis.IDENTITY
			check(arrow.begin_drag(hand),"straight-on trigger starts signed depth drag at view %.2f" % scale_)
			var axis: Vector3=arrow._drag_axis
			hand.global_position+=axis*0.005*scale_
			arrow.update_drag(hand)
			check(is_equal_approx(wb.depth_mm,sign_*10+5),"5 mm motion remains 5 CAD mm through zoom and sign")
			arrow.end_drag(true)
			check(is_equal_approx(wb.depth_mm,sign_*10),"B cancellation restores initial depth")
	doc.view_transform=Transform3D.IDENTITY
	wb.depth_mm=10;wb.extrude_arrow.refresh()
	for x in [-0.15,0.15]:
		var arrow=wb.extrude_arrow
		hand.global_position=arrow.tip_point+Vector3(x,0,0.2);hand.look_at(arrow.tip_point)
		check(arrow.begin_drag(hand),"either-side ray starts dragging")
		hand.global_position+=arrow._drag_axis*0.007
		hand.look_at(arrow.tip_point+arrow._drag_axis*0.007)
		arrow.update_drag(hand)
		check(is_equal_approx(wb.depth_mm,17),"oblique laser drag follows extrusion axis")
		arrow.end_drag(true)
	check(doc.snapshot()==before,"dragging and cancelling do not alter document or history data")
	for depth in [-30.0,30.0]:
		wb.depth_mm=depth;wb.extrude_arrow.refresh();wb.extrude_preview.refresh(0)
		var mesh: Mesh=wb.extrude_preview.tool_mesh.mesh
		var local:=Doc.unpack_transform(doc.sketch(id).plane).affine_inverse()
		var low:=INF;var high:=-INF
		for point in mesh.get_faces():
			var z: float=(local*point).z;low=minf(low,z);high=maxf(high,z)
		check(is_equal_approx(low,minf(0,depth)) and is_equal_approx(high,maxf(0,depth)),"live preview has exact signed mm bounds")
	wb.depth_mm=10
	check(await wb.extrude(),"apply still builds final CAD geometry")
	var body_id: int=doc.bodies[0].id
	var plane:=Doc.unpack_transform(doc.sketch(id).plane);plane.origin+=plane.basis.z*10
	id=doc.new_sketch(plane,body_id);doc.set_profile(id,"circle",[[0,0],[5,0]],true)
	wb.active_sketch=id;wb.selected_body=body_id;wb.operation="Remove";wb.depth_mm=-10
	wb.ui.show_command("extrude");wb.extrude_arrow.refresh()
	before=doc.snapshot()
	wb.extrude_preview.refresh(0.2)
	await frames()
	check(wb.extrude_preview.result_mesh.visible,"settled Remove preview shows actual boolean result")
	check(not doc.get_node("Part_"+str(body_id)+"/MeshInstance3D").visible,"boolean preview temporarily replaces original mesh")
	check(Doc.volume(Doc.faces_from_mesh(wb.extrude_preview.result_mesh.mesh))<Doc.volume(doc.body(body_id).faces),"Remove preview actually cuts volume")
	check(doc.snapshot()==before,"boolean preview leaves saved/export geometry untouched")
	print("EXTRUDE PREVIEW TIME: %.2f ms including two frames" % wb.extrude_preview.last_build_ms)
	wb.ui.show_command("select");wb.extrude_preview.refresh(0)
	check(not wb.extrude_preview.result_mesh.visible and doc.get_node("Part_"+str(body_id)+"/MeshInstance3D").visible,"leaving command restores original solid")
	var label: Label3D=wb.sketch_visual.label("Ø109.44",Vector3.ZERO,Color("147bd1"))
	check(not label.shaded and label.no_depth_test and label.render_priority>0 and label.outline_render_priority<label.render_priority,"dimension ink renders after translucent plane and its own outline")
	print("EXTRUDE DRAG RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
