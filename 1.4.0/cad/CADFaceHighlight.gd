extends MeshInstance3D
## Highlight original triangles of one connected planar face. Holes stay open.
var workbench: Node3D
var _cad_source:=true
var _normal:=Vector3.BACK
var _point:=Vector3.ZERO
func _process(_delta):
	if not visible or not mesh or not is_instance_valid(workbench): return
	var pose: Transform3D=workbench.document.view_transform if _cad_source else Transform3D.IDENTITY
	transform=pose
	var normal: Vector3=(pose.basis*_normal).normalized()
	var at: Vector3=pose*(_point*0.001)
	var side:=1.0 if normal.dot(workbench.camera.global_position-at)>=0 else -1.0
	# Same physical separation as the plane, on the viewer-facing side.
	global_position+=normal*side*0.0007*XRServer.world_scale

static func key(p: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [p.x,p.y,p.z]
func rebuild(hit: Dictionary,view: Transform3D):
	mesh=null
	if hit.is_empty(): return
	_cad_source=int(hit.source.id)>=0
	_normal=hit.normal; _point=hit.point_mm
	var faces: Array=hit.source.faces
	var normal: Vector3=hit.normal
	var point: Vector3=hit.point_mm
	var candidates: Dictionary={}
	var neighbors: Dictionary={}
	for i in range(0,faces.size(),3):
		var points: Array=[]
		for j in 3: points.append(Vector3(faces[i+j][0],faces[i+j][1],faces[i+j][2]))
		if points.any(func(v):return absf(normal.dot(v-point))>0.01): continue
		var face_normal: Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
		if absf(face_normal.dot(normal))<0.999: continue
		candidates[i]=points
		for p in points:
			var k:=key(p)
			if not neighbors.has(k): neighbors[k]=[]
			neighbors[k].append(i)
	var seed:=int(hit.get("triangle",-1))
	if not candidates.has(seed): return
	var pending: Array=[seed]
	var chosen: Dictionary={seed:true}
	while not pending.is_empty():
		var i: int=pending.pop_back()
		for p in candidates[i]:
			for other in neighbors[key(p)]:
				if not chosen.has(other): chosen[other]=true; pending.append(other)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in chosen:
		for p in candidates[i]: surface.add_vertex(p*0.001)
	mesh=surface.commit()
	var m:=StandardMaterial3D.new()
	m.albedo_color=Color(1.0,0.45,0.02,0.95)
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode=BaseMaterial3D.CULL_DISABLED
	m.render_priority=4
	material_override=m
	transform=view if int(hit.source.id)>=0 else Transform3D.IDENTITY
