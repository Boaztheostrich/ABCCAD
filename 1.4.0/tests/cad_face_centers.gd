extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("FACE CENTER FAIL: "+text_)
	else: print("FACE CENTER PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false)
	for shape in ["circle","rectangle"]:
		var plane:=Transform3D(Basis.from_euler(Vector3(0.3,0.6,0.2)),Vector3(120,1150,-650))
		var id: int=doc.new_sketch(plane)
		doc.set_profile(id,shape,[[45,30],[65,45] if shape=="rectangle" else [70,30]],true)
		check(await doc.extrude(id,12,"New"),"create offset rotated "+shape)
		var body: Dictionary=doc.bodies[-1]
		var hit: Dictionary={"normal":plane.basis.z,"point_mm":plane*Vector3(50,35,12),"source":{"id":body.id,"faces":body.faces}}
		var face: Transform3D=wb.face_sketch_plane(hit)
		check(face.origin.distance_to(plane*Vector3(45,30,12))<0.002,"new "+shape+" face sketch is centered on the face")
		check(face.basis.y.dot(plane.basis.y)>0.9999 and face.basis.z.dot(plane.basis.z)>0.9999,"centering retains part orientation")
	# Offset circle reference tests ensure origin cannot mask the center snap.
	var id: int=doc.new_sketch(Transform3D.IDENTITY)
	var edges: Array=[]
	var center:=Vector2(35,25)
	for i in 96: edges.append([center+Vector2.from_angle(TAU*i/96)*20,center+Vector2.from_angle(TAU*(i+1)/96)*20])
	check(doc.add_projected_edges(id,edges),"project offset circular edge")
	var s: Dictionary=doc.sketch(id)
	check(s.projected_centers.size()==1 and Vector2(s.projected_centers[0][0],s.projected_centers[0][1]).distance_to(center)<0.001,"projection stores exact offset center")
	var snap: Dictionary=doc.infer_point(id,center+Vector2(1,1),5)
	check(snap.constraint.get("kind")=="projected_center" and snap.point.distance_to(center)<0.001,"pointer snaps to projected center")
	doc.set_profile(id,"line",[[35,25],[65,25]],false)
	doc.add_inference(id,0,snap.constraint)
	check(s.constraints[0].kind=="projected_center","center snap becomes a retained constraint")
	check(await doc.dimension(id,"length:1",40),"center-anchored line accepts driving length")
	check(Vector2(s.points[0][0],s.points[0][1]).distance_to(center)<0.001,"length edit preserves projected center anchor")
	check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"projected center and reference persist through JSON validation")
	var save: Dictionary=doc.snapshot();doc.load_document(save)
	check(doc.sketch(id).projected_centers.size()==1,"reload restores projected center")
	doc.sketch(id).erase("projected_centers")
	check(doc.add_projected_edges(id,edges) and doc.sketch(id).projected_centers.size()==1,"re-projecting an older rim adds its missing center")
	var bad:=save.duplicate(true);bad.sketches[-1].projected_centers=[[INF,0]]
	check(not Doc.validate(bad).is_empty(),"invalid saved center coordinates reject")
	print("FACE CENTER RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
