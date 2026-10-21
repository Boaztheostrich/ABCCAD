extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("FACE CUT FAIL: "+text_)
	else: print("FACE CUT PASS: "+text_)
func hit(faces: Array,from: Vector3,direction: Vector3) -> float:
	# Scalar doubles avoid float Vector3 barycentric tolerance admitting a ray
	# just outside a very thin CSG triangle at room-scale millimeter positions.
	var closest:=INF
	for i in range(0,faces.size(),3):
		var a: Array=faces[i];var b: Array=faces[i+1];var c: Array=faces[i+2]
		var ux: float=b[0]-a[0];var uy: float=b[1]-a[1];var uz: float=b[2]-a[2]
		var vx: float=c[0]-a[0];var vy: float=c[1]-a[1];var vz: float=c[2]-a[2]
		var px: float=direction.y*vz-direction.z*vy;var py: float=direction.z*vx-direction.x*vz;var pz: float=direction.x*vy-direction.y*vx
		var determinant: float=ux*px+uy*py+uz*pz
		if absf(determinant)<0.0000000001:continue
		var tx: float=from.x-a[0];var ty: float=from.y-a[1];var tz: float=from.z-a[2]
		var u: float=(tx*px+ty*py+tz*pz)/determinant
		if u<0 or u>1:continue
		var qx: float=ty*uz-tz*uy;var qy: float=tz*ux-tx*uz;var qz: float=tx*uy-ty*ux
		var v: float=(direction.x*qx+direction.y*qy+direction.z*qz)/determinant
		if v<0 or u+v>1:continue
		var t: float=(vx*qx+vy*qy+vz*qz)/determinant
		if t>=0:closest=minf(closest,t)
	return closest
func stl_faces(bytes: PackedByteArray) -> Array:
	var faces: Array=[]
	for i in bytes.decode_u32(80):
		for j in 3:
			var at:=84+i*50+12+j*12
			faces.append([bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8)])
	return faces
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false)
	for orientation in 12:
		var basis:=Basis.IDENTITY if orientation==0 else Basis.from_euler(Vector3(0.17,0.31,0.13)*orientation)
		for side in [-1,1]:
			for cut_depth in [-54.0,-10.0,-5.0]:
				doc.clear_all()
				var plane:=Transform3D(basis,Vector3(1223.465,1156.737,-675.231))
				var id: int=doc.new_sketch(plane)
				doc.set_profile(id,"rectangle",[[0,0],[100,100]],true)
				check(await doc.extrude(id,10,"New"),"plate %d %d" % [orientation,side])
				var bid: int=doc.bodies[0].id
				var hole: int=doc.new_sketch(plane,bid)
				doc.set_profile(hole,"circle",[[0,0],[35,0]],true)
				check(await doc.extrude(hole,10,"Remove"),"base plane cut")
				if orientation%2==1:
					var attached: Dictionary={}
					for sk in doc.sketches: attached[int(sk.id)]=sk.duplicate(true)
					var delta:=Transform3D(Basis.from_euler(Vector3(0.14,-0.23,0.17)),Vector3(125,-47,78))
					doc.apply_body_pose(bid,doc.body(bid).duplicate(true),attached,delta)
					plane=delta*plane
				# Pick a point beside the central hole, then use the exact UI face plane.
				var local:=Vector3(-60,-60,10 if side==1 else 0)
				var ray: Vector3=plane*(local+Vector3(0,0,side*50))
				wb.select_face(ray*0.001,-plane.basis.z*side)
				check(not wb.selected_hit.is_empty(),"pick actual post-boolean solid face")
				var face: Transform3D=wb.face_sketch_plane(wb.selected_hit)
				wb.new_sketch(true);hole=wb.active_sketch
				var local_center: Vector3=face.affine_inverse()*(plane*local)
				doc.set_profile(hole,"circle",[[local_center.x,local_center.y],[local_center.x+8,local_center.y]],true)
				if orientation==1 and side==1 and cut_depth==-54:
					wb.selected_body=bid;wb.active_sketch=hole;wb.operation="Remove";wb.depth_mm=cut_depth
					wb.ui.show_command("extrude");wb.extrude_arrow.refresh()
					var before: Dictionary=doc.snapshot()
					wb.extrude_preview.refresh(0.2)
					for frame in 4:await get_tree().process_frame
					check(wb.extrude_preview.result_mesh.visible,"face cut settled preview is available")
					var preview: Array=Doc.faces_from_mesh(wb.extrude_preview.result_mesh.mesh)
					check(is_inf(hit(preview,plane*Vector3(local.x,local.y,11),-plane.basis.z)),"face cut preview has an open through hole")
					check(doc.snapshot()==before,"face cut preview preserves saved geometry")
					wb.extrude_preview.cancel()
				check(await doc.extrude(hole,cut_depth,"Remove"),"face-based inward through cut")
				var blocked:=0
				var near_face:=0
				for offset in [Vector2.ZERO,Vector2(3,0),Vector2(-3,0),Vector2(0,3),Vector2(0,-3)]:
					for direction in [-1,1]:
						var start: Vector3=plane*Vector3(local.x+offset.x,local.y+offset.y,-1 if direction==1 else 11)
						var distance:=hit(doc.bodies[0].faces,start,plane.basis.z*direction)
						if (not is_inf(distance) if cut_depth<=-10 else absf(distance-(1.0 if direction==side else 6.0))>0.002):
							print("BLOCK DETAIL ",orientation," side ",side," depth ",cut_depth," offset ",offset," dir ",direction," dist ",distance)
							blocked+=1
							if distance<1.1:near_face+=1
				check(blocked==0,"face cut open both sides %d %d depth %.0f (blocked %d, at surface %d)" % [orientation,side,cut_depth,blocked,near_face])
				var exported: Array=doc.print_export_faces(bid)
				var bytes: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(exported))
				var frame: Transform3D=doc.print_frame_mm(bid)
				var source: Array=doc.bodies[0].faces[0]
				var shift:=Vector3(exported[0][0],exported[0][1],exported[0][2])-frame*Vector3(source[0],source[1],source[2])
				var export_start: Vector3=frame*(plane*Vector3(local.x,local.y,11 if side==1 else -1))+shift
				var export_direction: Vector3=frame.basis*(-plane.basis.z*side)
				var export_hit:=hit(stl_faces(bytes),export_start,export_direction)
				check(is_inf(export_hit) if cut_depth<=-10 else absf(export_hit-6)<0.002,"serialized STL retains through hole or exact blind floor")
				if blocked>0:
					var f:=FileAccess.open("/private/tmp/abccad-face-cut-failure.json",FileAccess.WRITE);f.store_string(JSON.stringify(doc.snapshot()))
	print("FACE CUT RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
