extends Node3D
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,label_: String):
	checks+=1
	if not ok: failures+=1;push_error("CAD STL FAIL: "+label_)
	else: print("CAD STL PASS: "+label_)
func read_faces(bytes: PackedByteArray) -> Array:
	var faces: Array=[]
	for i in bytes.decode_u32(80):
		for j in 3:
			var at:=84+i*50+12+j*12
			faces.append([bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8)])
	return faces
func stats(bytes: PackedByteArray) -> Dictionary:
	var faces:=read_faces(bytes)
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	var volume:=0.0;var agree:=true;var edges: Dictionary={}
	var origin:=Vector3(faces[0][0],faces[0][1],faces[0][2])
	for i in range(0,faces.size(),3):
		var p: Array=[]
		for j in 3:
			var v:=Vector3(faces[i+j][0],faces[i+j][1],faces[i+j][2]);p.append(v)
			low=low.min(v);high=high.max(v)
		var at:=84+(i/3)*50
		var normal:=Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8))
		agree=agree and normal.dot((p[1]-p[0]).cross(p[2]-p[0]).normalized())>0.999
		volume+=(p[0]-origin).dot((p[1]-origin).cross(p[2]-origin))/6
		for j in 3:
			var a: String="%.4f,%.4f,%.4f" % [p[j].x,p[j].y,p[j].z]
			var b: String="%.4f,%.4f,%.4f" % [p[(j+1)%3].x,p[(j+1)%3].y,p[(j+1)%3].z]
			var edge:=a+"/"+b if a<b else b+"/"+a
			if not edges.has(edge): edges[edge]=[0,0]
			edges[edge][0]+=1;edges[edge][1]+=1 if a<b else -1
	var closed:=true
	for edge in edges.values():closed=closed and edge[0]==2 and edge[1]==0
	return {"low":low,"size":high-low,"volume":volume,"normals":agree,"closed":closed}
func _ready():
	var supplied:=FileAccess.get_file_as_bytes("res://tests/fixtures/stl-regression/abccad-cube-inward.stl")
	var baseline:=FileAccess.get_file_as_bytes("res://tests/fixtures/stl-regression/onshape-cube.stl")
	check(stats(supplied).volume<0 and not stats(supplied).normals,"supplied ABCCAD file reproduces inward winding and mismatched normals")
	check(stats(baseline).volume>0 and stats(baseline).normals and stats(baseline).closed,"supplied Onshape file has correct outward closed STL")
	var repaired: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(read_faces(supplied)))
	var repaired_stats:=stats(repaired)
	check(repaired_stats.volume>0 and repaired_stats.normals and repaired_stats.closed,"updated writer repairs the exact failing cube without changing its triangles")
	check(absf(repaired_stats.volume-1000000)<2,"winding repair retains the original cube's 1000000 mm3 volume")
	var imported: Mesh=STLIO.Importer.LoadFromBytes(repaired)
	var again: PackedByteArray=STLIO.Exporter.SaveToBytes(imported)
	check(stats(again).volume>0 and stats(again).normals,"standard STL imports into Godot and re-exports with outward normals")
	for name_ in ["Front","Top","Right"]:
		for sign_ in [-1,1]:
			var doc:=Doc.new();add_child(doc)
			var id: int=doc.new_sketch(doc.base_plane(name_))
			doc.set_profile(id,"rectangle",[[0,0],[50,50]],true)
			check(await doc.extrude(id,sign_*100,"New"),"create signed 100 mm cube on "+name_)
			var body_id: int=doc.bodies[0].id
			var before: Dictionary=doc.snapshot()
			var bytes: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(doc.print_export_faces(body_id)))
			var flat:=stats(bytes)
			if name_=="Top" and sign_==1:
				var file:=FileAccess.open("res://builds/ABCCAD_export_validation_cube.stl",FileAccess.WRITE);file.store_buffer(bytes);file.close()
			check(flat.size.distance_to(Vector3(100,100,100))<0.001 and flat.low.distance_to(Vector3(-50,-50,0))<0.001,"cube exports centered and bed-flat in mm from "+name_)
			check(flat.normals and flat.closed and absf(flat.volume-1000000)<2,"cube has a closed outward surface on "+name_)
			# Simulate room placement/grabbing: design frame and geometry rotate together.
			var pose:=Transform3D(Basis.from_euler(Vector3(0.16,-0.12,0.09)),Vector3(183,-116,247))
			var attached: Dictionary={id:doc.sketch(id).duplicate(true)}
			doc.apply_body_pose(body_id,doc.bodies[0].duplicate(true),attached,pose)
			var placed_before: Dictionary=doc.snapshot()
			bytes=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(doc.print_export_faces(body_id)))
			var placed:=stats(bytes)
			check(placed.size.distance_to(Vector3(100,100,100))<0.002 and placed.low.distance_to(Vector3(-50,-50,0))<0.002,"room movement/rotation no longer tilts the exported design on "+name_)
			check(placed.normals and placed.volume>0 and doc.snapshot()==placed_before,"print normalization preserves live geometry and solid orientation")
			doc.queue_free()
	# A through-hole must retain inward-facing cavity walls within an outward shell.
	var doc:=Doc.new();add_child(doc)
	var id: int=doc.new_sketch(doc.base_plane("Top"));doc.set_profile(id,"rectangle",[[0,0],[20,20]],true)
	await doc.extrude(id,10,"New");var body_id: int=doc.bodies[0].id
	var cut: int=doc.new_sketch(doc.base_plane("Top"),body_id);doc.set_profile(cut,"circle",[[0,0],[5,0]],true)
	check(await doc.extrude(cut,10,"Remove"),"create through-hole STL case")
	var output: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(doc.print_export_faces(body_id)))
	var ring:=stats(output)
	check(ring.normals and ring.volume>0,"cut body preserves correct normal/winding agreement including cavity walls")
	var no_cap:=true;var faces:=read_faces(output)
	for i in range(0,faces.size(),3):
		var p: Array=[]
		for j in 3:p.append(Vector3(faces[i+j][0],faces[i+j][1],faces[i+j][2]))
		if Geometry3D.ray_intersects_triangle(Vector3(0,0,20),Vector3(0,0,-1),p[0],p[1],p[2])!=null:no_cap=false
	check(no_cap,"actual serialized STL keeps the through-hole open")
	# One common frame/translation must retain assembly spacing and rotation.
	var frame:=doc.print_frame_mm()
	var all: Array=doc.bodies[0].faces.duplicate(true)
	for p in doc.bodies[0].faces:all.append([p[0]+63,p[1]+21,p[2]-14])
	var normalized:=Doc.print_ready_faces(all,frame)
	var half: int=all.size()/2
	var original_delta:=Vector3(all[half][0]-all[0][0],all[half][1]-all[0][1],all[half][2]-all[0][2])
	var actual_delta:=Vector3(normalized[half][0]-normalized[0][0],normalized[half][1]-normalized[0][1],normalized[half][2]-normalized[0][2])
	check(actual_delta.distance_to(frame.basis*original_delta)<0.001,"whole-assembly normalization preserves relative part offsets")
	var exporter:=preload("res://VoxelExporter.gd").new();add_child(exporter)
	var block=load("res://cube.tscn").instantiate();add_child(block);block.freeze=true
	block.set_meta("shape_type","cube");block.global_position=Vector3(0.35,1.3,-0.65)
	block.get_node("VoxelLogic")._on_dropped(block)
	var raw: Array=Doc.faces_from_mesh(exporter.build_export_mesh(1000))
	var expected:=Doc.print_ready_faces(raw,doc.print_frame_mm())
	var actual: Array=Doc.faces_from_mesh(exporter.build_print_export_mesh(1000))
	var aligned: bool=actual.size()==expected.size()
	for i in actual.size():
		if Vector3(actual[i][0],actual[i][1],actual[i][2]).distance_to(Vector3(expected[i][0],expected[i][1],expected[i][2]))>0.001:aligned=false
	check(aligned,"actual combined export preserves CAD/block alignment with a single print frame")
	var combined: PackedByteArray=STLIO.Exporter.SaveToBytes(exporter.build_print_export_mesh(1000))
	check(stats(combined).normals and stats(combined).volume>0 and absf(stats(combined).low.z)<0.001,"combined exported assembly has outward normals and rests on print bed")
	var output_file:=FileAccess.open("res://builds/ABCCAD_export_validation_assembly.stl",FileAccess.WRITE);output_file.store_buffer(combined);output_file.close()
	print("CAD STL RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
