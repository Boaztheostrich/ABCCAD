extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("ALIGN REUSE FAIL: "+text_)
	else: print("ALIGN REUSE PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	doc.set_profile(id,"line",[[0,0],[60,0],[60,60]],false)
	doc.add_inference(id,0,{"kind":"origin"});doc.add_inference(id,1,{"kind":"horizontal"});doc.add_inference(id,2,{"kind":"vertical"})
	var snap: Dictionary=doc.infer_point(id,Vector2(3,62),30)
	check(snap.point.distance_to(Vector2(0,60))<0.001,"fourth corner aligns above origin and level with previous endpoint")
	check(snap.constraint.kind=="horizontal" and snap.constraint.also[0].kind=="vertical_align","inference combines horizontal segment and vertical point alignment")
	check(snap.guides.size()==1 and snap.guides[0][0]==Vector2.ZERO,"alignment gives a visible guide from the reference point")
	doc.set_profile(id,"line",[[0,0],[60,0],[60,60],[0,60]],false)
	doc.add_inference(id,3,snap.constraint)
	check(doc.sketch(id).constraints.any(func(c):return c.kind=="vertical_align" and int(c.index)==0),"vertical alignment is stored as a constraint")
	check(await doc.dimension(id,"length:1",61.4),"set width after alignment")
	check(await doc.dimension(id,"length:2",60.6),"set height after alignment")
	var s: Dictionary=doc.sketch(id)
	check(absf(s.points[3][0])<0.001 and absf(s.points[3][1]-60.6)<0.001,"alignment survives driving dimension edits")
	check(doc.constraint_states()[id].fully_defined,"aligned corner becomes black once the rectangle is dimensioned")
	check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"alignment references survive save validation")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()));doc.load_document(saved)
	check(doc.sketch(id).constraints.any(func(c):return c.kind=="vertical_align"),"reload retains vertical alignment")
	wb.active_sketch=id;wb.end_sketch_tool();var count: int=doc.sketches.size();wb.resume_lines()
	check(wb.active_sketch==id and wb.tool=="line" and not wb._chain_ended and doc.sketches.size()==count,"Resume lines continues the same ended open sketch")
	wb.close_profile();var original: Dictionary=doc.sketch(id).duplicate(true)
	wb.start_extend_vertex();check(wb.extend_vertex(Vector2(60,60)),"From vertex starts a connected chain on a closed profile")
	check(doc.sketch(id)==original and wb.active_sketch!=id and doc.sketch(wb.active_sketch).constraints[0].target==id,"extension preserves closed profile and references selected vertex")
	wb.start_use_edge();wb.end_sketch_tool();check(wb.tool=="select","B cancels edge reuse mode")
	check(await doc.extrude(id,12,"New"),"aligned profile extrudes without losing dimensions")
	var exported: Array=doc.export_faces(doc.bodies[-1].faces)
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	for p in exported:
		var v:=Vector3(p[0],p[1],p[2]);low=low.min(v);high=high.max(v)
	check((high-low).distance_to(Vector3(61.4,60.6,12))<0.01,"exported aligned profile has exact 61.4 by 60.6 by 12 mm bounds")
	check(Doc.validate(doc.snapshot()).is_empty(),"aligned extrusion and dependent extension save together")
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1,"origin_mm":[0,1150,-650]})
	# Build a rectangular part and inspect exact face edges.
	wb.new_base_sketch("Front");id=wb.active_sketch
	doc.set_profile(id,"rectangle",[[0,0],[20,15]],true);check(await wb.extrude(),"create body for edge conversion")
	var body_id: int=doc.bodies[-1].id
	var plane:=Doc.unpack_transform(doc.sketch(id).plane)
	wb.select_face((plane*Vector3(18,0,11))*0.001,-plane.basis.z)
	var edges: Array=preload("res://cad/CADFaceEdges.gd").boundary(wb.selected_hit)
	check(edges.size()==4,"edge picker removes triangulation diagonal from rectangular face")
	wb.new_sketch(true);var face_id: int=wb.active_sketch
	var hand:=Node3D.new();add_child(hand)
	hand.global_position=(plane*Vector3(19,0,50))*0.001;hand.global_basis=plane.basis
	var edge: Dictionary=wb.edge_hit(hand)
	check(not edge.is_empty() and is_equal_approx(edge.points[0].distance_to(edge.points[1]),30),"laser selects and projects a real 30 mm object edge")
	var before_body: Dictionary=doc.body(body_id).duplicate(true)
	check(wb.use_edge(edge) and wb.active_sketch==face_id,"edge populates the empty active sketch")
	check(doc.sketch(face_id).projected_edges.size()==1 and not doc.sketch(face_id).closed and wb.tool=="use_edge","Project remains active after copying an independent edge")
	check(doc.body(body_id)==before_body,"projecting an edge leaves source solid/export unchanged")
	check(not wb.use_edge(edge) and wb.active_sketch==face_id and doc.sketch(face_id).projected_edges.size()==1,"duplicate projection preserves the existing sketch")
	# Rotated part: face axes follow its actual frame, Top remains ground aligned.
	var rotation:=Basis(Vector3.BACK,0.38)
	var baseline: Dictionary=doc.body(body_id).duplicate(true);var attached: Dictionary={}
	for sketch in doc.sketches:
		if int(sketch.body_id)==body_id: attached[int(sketch.id)]=sketch.duplicate(true)
	doc.apply_body_pose(body_id,baseline,attached,Transform3D(rotation,Vector3.ZERO))
	var normal: Vector3=rotation*plane.basis.z
	var point: Vector3=rotation*(plane*Vector3(0,0,10))
	var hit: Dictionary={"normal":normal,"point_mm":point,"source":{"id":body_id,"block":null}}
	var face: Transform3D=wb.face_sketch_plane(hit)
	check(absf(face.basis.y.dot(rotation*plane.basis.y))>0.9999,"new face sketch keeps the rotated part's in-plane orientation")
	check(absf(face.basis.z.dot(normal))>0.9999 and absf((face.origin-point).dot(normal))<0.001,"face plane remains exactly coplanar with its source")
	check(doc.base_plane("Top").basis.z.dot(Vector3.UP)>0.9999,"default Top remains parallel with ground")
	# Presentation bias changes neither exact interaction plane nor saved data.
	wb._redraw();var before: Dictionary=doc.snapshot()
	var quad=wb.plane_display.get_children().filter(func(n):return n.get_meta("sketch_plane",false))[0]
	for scale_ in [0.2,1.0,8.43]:
		wb.plane_display.transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_),Vector3.ZERO)
		for side in [-1,1]:
			var logical: Transform3D=wb.plane_display.global_transform*quad.logical_pose
			wb.camera.global_position=logical.origin+logical.basis.z.normalized()*side*0.4
			quad.update_depth_bias()
			var offset: Vector3=quad.global_position-logical.origin
			check(offset.dot(wb.camera.global_position-logical.origin)<0 and is_equal_approx(offset.length(),0.0007*XRServer.world_scale),"plane drawing is biased behind coplanar solid from either side at view %.2f" % scale_)
	check(doc.snapshot()==before,"anti-flicker rendering never changes saved sketch planes or dimensions")
	check(Doc.validate(doc.snapshot()).is_empty(),"reused edges and extensions remain valid CAD data")
	print("ALIGN REUSE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
