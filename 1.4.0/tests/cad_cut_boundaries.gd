extends Node3D
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,label_: String):
	checks+=1
	if not ok: failures+=1; push_error("CUT FAIL: "+label_)
	else: print("CUT PASS: "+label_)
func hit(faces: Array,from: Vector3,direction: Vector3) -> float:
	var closest:=INF
	for i in range(0,faces.size(),3):
		var a:=Vector3(faces[i][0],faces[i][1],faces[i][2])
		var b:=Vector3(faces[i+1][0],faces[i+1][1],faces[i+1][2])
		var c:=Vector3(faces[i+2][0],faces[i+2][1],faces[i+2][2])
		var point: Variant=Geometry3D.ray_intersects_triangle(from,direction,a,b,c)
		if point!=null: closest=minf(closest,from.distance_to(point))
	return closest
func _ready():
	for rotated in [false,true]:
		var plane:=Transform3D(Basis.from_euler(Vector3(0.31,0.53,-0.19)) if rotated else Basis.IDENTITY,Vector3(1234,1150,-650))
		for reverse in [false,true]:
			var doc:=Doc.new(); add_child(doc)
			var id: int=doc.new_sketch(plane)
			doc.set_profile(id,"rectangle",[[0,0],[25,20]])
			check(await doc.extrude(id,10,"New"),"base solid")
			var body: int=doc.bodies[0].id
			var start:=plane
			if reverse: start.origin+=start.basis.z*10
			var cut: int=doc.new_sketch(start,body)
			doc.set_profile(cut,"circle",[[0,0],[5,0]])
			check(await doc.extrude(cut,-10 if reverse else 10,"Remove"),"coplanar exact-depth through cut")
			var faces: Array=doc.bodies[0].faces
			for side in [-1,1]:
				var from: Vector3=plane*Vector3(0,0,-1 if side==1 else 11)
				check(is_inf(hit(faces,from,plane.basis.z*side)),"no retained first/last face in hole from side %d rotated %s reversed %s" % [side,rotated,reverse])
			var expected: float=20000-96*sin(TAU/96.0)*25/2*10
			check(absf(Doc.volume(faces)-expected)<1,"through cut preserves outer bounds and exact ring volume")
			var exported: Array=Doc.faces_from_mesh(Doc.mesh_from_faces(doc.export_faces(faces)))
			check(is_inf(hit(exported,plane*Vector3(0,0,-1),plane.basis.z)),"exported STL source has no capping layer")
			doc.queue_free()
		var doc:=Doc.new(); add_child(doc)
		var id: int=doc.new_sketch(plane)
		doc.set_profile(id,"rectangle",[[0,0],[25,20]])
		await doc.extrude(id,10,"New")
		var start:=plane; start.origin+=plane.basis.z*10
		var cut: int=doc.new_sketch(start,int(doc.bodies[0].id))
		doc.set_profile(cut,"circle",[[0,0],[5,0]])
		check(await doc.extrude(cut,-5,"Remove"),"blind cut")
		var distance: float=hit(doc.bodies[0].faces,plane*Vector3(0,0,11),-plane.basis.z)
		check(absf(distance-6)<0.002,"blind-cut floor remains exactly 5 mm deep")
		doc.queue_free()
	# A disc plus a raised boss reproduces the headset construction. Wrong-sign
	# Remove touches the end face but has no solid-volume overlap.
	for rotated in [false,true]:
		for reversed_plane in [false,true]:
			var plane:=Transform3D(Basis.from_euler(Vector3(0.31,0.53,-0.19)) if rotated else Basis.IDENTITY,Vector3(1234,1150,-650))
			var doc:=Doc.new(); add_child(doc)
			var id: int=doc.new_sketch(plane)
			doc.set_profile(id,"circle",[[0,0],[30,0]])
			check(await doc.extrude(id,5,"New"),"wrong-direction repro disc")
			var bid: int=doc.bodies[0].id
			var boss_plane:=plane; boss_plane.origin+=plane.basis.z*5
			var boss: int=doc.new_sketch(boss_plane,bid)
			doc.set_profile(boss,"rectangle",[[0,0],[10,10]])
			check(await doc.extrude(boss,10,"Add"),"wrong-direction repro raised boss")
			var face:=plane
			face.origin+=plane.basis.z*15
			if reversed_plane: face.basis=face.basis*Basis(Vector3.RIGHT,PI)
			var hole: int=doc.new_sketch(face,bid)
			doc.set_profile(hole,"circle",[[0,0],[3,0]])
			var before: Dictionary=doc.snapshot()
			var history: int=doc.undo_steps.size()
			var wrong_depth: float=-30 if reversed_plane else 30
			check(not await doc.extrude(hole,wrong_depth,"Remove"),"outward touching Remove is rejected for either sketch normal")
			check(doc.snapshot()==before and doc.undo_steps.size()==history,"rejected outward cut preserves geometry, features and undo")
			check(not await doc.extrude(hole,wrong_depth,"Remove") and doc.snapshot()==before,"repeated wrong-sign Remove cannot accumulate a membrane")
			check(await doc.extrude(hole,-wrong_depth,"Remove"),"reversing depth after rejection makes valid through cut")
			check(is_inf(hit(doc.bodies[0].faces,plane*Vector3(0,0,16),-plane.basis.z)),"corrected through hole is open through boss and disc")
			doc.queue_free()
	print("CUT BOUNDARY RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
