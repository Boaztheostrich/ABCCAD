extends Node3D
## Model coordinates and triangle caches are millimeters. View scale never edits them.
const Constraints = preload("res://cad/CADConstraints.gd")
const SketchConstraints = preload("res://cad/CADSketchConstraints.gd")
signal history_applied(before: Dictionary, after: Dictionary)
signal changed
signal status(message: String)
var bodies: Array = []
var sketches: Array = []
var next_id := 1
var origin_mm := Vector3(0,1150,-650)
# Heading of the base construction planes; existing sketches retain their frame.
var origin_yaw := 0.0
var undo_steps: Array = []
var redo_steps: Array = []
var busy := false
var active_grabs: Dictionary = {}
var reference_plane: Dictionary = {}
var deleted_conversions: Array=[]
# Presentation only: never serialized or read by the STL exporter.
var view_transform := Transform3D.IDENTITY
var history_guard: Callable

func _ready():
	add_to_group("cad_document")

static func pack_transform(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

static func unpack_transform(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])),Vector3(a[9],a[10],a[11]))

func body(id: int) -> Dictionary:
	for b in bodies:
		if int(b.id) == id: return b
	return {}

func sketch(id: int) -> Dictionary:
	for s in sketches:
		if int(s.id) == id: return s
	return {}

func sketch_root(id: int) -> int:
	var s:=sketch(id)
	return int(s.get("group_id",id)) if not s.is_empty() else id

func sketch_members(id: int) -> Array:
	var root:=sketch_root(id)
	return sketches.filter(func(s):return int(s.get("group_id",s.id))==root)

func sketch_roots() -> Array:
	return sketches.filter(func(s):return not s.has("group_id"))

func sketch_shape_count(id: int) -> int:
	return sketch_members(id).filter(func(s):return s.points.size()>=2 or not s.get("projected_edges",[]).is_empty()).size()

func new_entity(id: int,kind: String="line") -> int:
	var root:=sketch_root(id)
	var source:=sketch(root)
	if busy or source.is_empty():return -1
	checkpoint()
	var entity_id:=next_id;next_id+=1
	sketches.append({"id":entity_id,"group_id":root,"body_id":source.body_id,"plane":source.plane.duplicate(),"kind":kind,"points":[],"closed":false,"constraints":[]})
	changed.emit()
	return entity_id

func sketch_regions(id: int) -> Array:
	return load("res://cad/CADSketchRegions.gd").build(sketch_members(id))

static func entity_geometry(entities: Array) -> Array:
	return entities.map(func(s):return [s.id,s.kind,s.points,s.plane,s.closed,s.get("projected_edges",[])])

func region_profile(id: int,selection: Array,known_regions: Array=[]) -> Dictionary:
	var root:=sketch(sketch_root(id))
	if root.is_empty():return {}
	var regions: Array=sketch_regions(id) if known_regions.is_empty() else known_regions
	var chosen: Array=regions.filter(func(r):return r.id in selection)
	if chosen.size()!=selection.size() or chosen.is_empty():return {}
	var result:=root.duplicate(true)
	result.closed=true
	result.region_ids=selection.duplicate()
	result.region_anchor=[chosen[0].anchor.x,chosen[0].anchor.y]
	result.region_profiles=load("res://cad/CADSketchRegions.gd").packed(chosen)
	result.region_entities=sketch_members(id).duplicate(true)
	return result

func extrude_regions(id: int,selection: Array,depth_mm: float,operation: String,target_id: int=-1) -> bool:
	var bundle:=region_profile(id,selection)
	if bundle.is_empty():status.emit("Please select the area or areas you want to extrude.");return false
	return await extrude(int(bundle.id),depth_mm,operation,target_id,bundle)

func snapshot() -> Dictionary:
	var result: Dictionary={"version":1,"bodies":bodies.duplicate(true),"sketches":sketches.duplicate(true),"next_id":next_id,"origin_mm":[origin_mm.x,origin_mm.y,origin_mm.z]}
	if origin_yaw != 0.0: result.origin_yaw=origin_yaw
	if not reference_plane.is_empty(): result.reference_plane=reference_plane.duplicate(true)
	if not deleted_conversions.is_empty(): result.deleted_conversions=deleted_conversions.duplicate()
	return result

func checkpoint():
	undo_steps.append(snapshot())
	if undo_steps.size() > 30: undo_steps.pop_front()
	redo_steps.clear()

func deletion_plan(id: int) -> Dictionary:
	if sketch(id).is_empty(): return {"sketches":[],"bodies":[]}
	var remove_sketches: Array=sketch_members(id).map(func(s):return int(s.id))
	var remove_bodies: Array=[]
	var changed_:=true
	while changed_:
		changed_=false
		for s in sketches:
			if int(s.id) in remove_sketches: continue
			if sketch_root(int(s.id)) in remove_sketches.map(func(sid):return sketch_root(int(sid))) or int(s.body_id) in remove_bodies or s.get("constraints",[]).any(func(c):return int(c.get("target",-1)) in remove_sketches):
				remove_sketches.append(int(s.id)); changed_=true
		for b in bodies:
			if int(b.id) in remove_bodies: continue
			for feature in b.features:
				if int(feature.sketch.id) in remove_sketches or feature.sketch.get("constraints",[]).any(func(c):return int(c.get("target",-1)) in remove_sketches):
					remove_bodies.append(int(b.id)); changed_=true; break
	return {"sketches":remove_sketches,"bodies":remove_bodies}

func delete_sketch(id: int) -> bool:
	if busy: return false
	var plan:=deletion_plan(id)
	if plan.sketches.is_empty(): return false
	checkpoint()
	_erase_geometry(plan.sketches,plan.bodies)
	status.emit("Sketch and confirmed dependent items deleted. Undo restores them.")
	return true

func clear_all() -> bool:
	if busy or (bodies.is_empty() and sketches.is_empty()): return false
	checkpoint()
	_erase_geometry(sketches.map(func(s):return int(s.id)),bodies.map(func(b):return int(b.id)))
	status.emit("CAD workspace cleared. Table reference and saved files kept. Undo restores the model.")
	return true

func _erase_geometry(sketch_ids: Array,body_ids: Array):
	for b in bodies:
		if int(b.id) in body_ids and b.has("converted_source") and not int(b.id) in deleted_conversions: deleted_conversions.append(int(b.id))
	sketches=sketches.filter(func(s):return not int(s.id) in sketch_ids)
	bodies=bodies.filter(func(b):return not int(b.id) in body_ids)
	rebuild_visuals()
	changed.emit()

func undo():
	if busy or undo_steps.is_empty(): return
	var before := snapshot()
	if history_guard.is_valid() and not history_guard.call(before,undo_steps.back()):
		status.emit("Undo would overlap a block placed since conversion. Move that block first.")
		return
	redo_steps.append(before)
	load_document(undo_steps.pop_back(), false)
	history_applied.emit(before,snapshot())

func redo():
	if busy or redo_steps.is_empty(): return
	var before := snapshot()
	if history_guard.is_valid() and not history_guard.call(before,redo_steps.back()):
		status.emit("Redo would overlap another block. Move that block first.")
		return
	undo_steps.append(before)
	load_document(redo_steps.pop_back(), false)
	history_applied.emit(before,snapshot())

func new_sketch(plane_mm: Transform3D, body_id: int = -1) -> int:
	if busy: return -1
	checkpoint()
	var id := next_id
	next_id += 1
	sketches.append({"id":id,"body_id":body_id,"plane":pack_transform(plane_mm),"kind":"line","points":[],"closed":false,"constraints":[]})
	changed.emit()
	return id

func add_projected_edge(id: int,a: Vector2,b: Vector2) -> bool:
	return add_projected_edges(id,[[a,b]])

func add_projected_edges(id: int,edges: Array) -> bool:
	var s:=sketch(id)
	if busy or s.is_empty(): return false
	var additions: Array=[]
	for edge in edges:
		var a: Vector2=edge[0];var b: Vector2=edge[1]
		if not a.is_finite() or not b.is_finite() or a.distance_to(b)<0.001: continue
		var duplicate:=false
		for existing in s.get("projected_edges",[])+additions:
			var x:=Vector2(existing[0][0],existing[0][1]);var y:=Vector2(existing[1][0],existing[1][1])
			if (a.distance_to(x)<0.001 and b.distance_to(y)<0.001) or (a.distance_to(y)<0.001 and b.distance_to(x)<0.001):
				duplicate=true;break
		if not duplicate: additions.append([[a.x,a.y],[b.x,b.y]])
	var circle:=preload("res://cad/CADFaceEdges.gd").circle_center(edges)
	var new_center:=false
	var center:=Vector2.ZERO
	if not circle.is_empty():
		center=circle.center
		new_center=not s.get("projected_centers",[]).any(func(p):return Vector2(p[0],p[1]).distance_to(center)<0.001)
	if additions.is_empty() and not new_center: return false
	checkpoint()
	if not s.has("projected_edges"): s.projected_edges=[]
	s.projected_edges.append_array(additions)
	if new_center:
		if not s.has("projected_centers"): s.projected_centers=[]
		s.projected_centers.append([center.x,center.y])
	refresh_projected_closure(s)
	changed.emit()
	return true

static func refresh_projected_closure(s: Dictionary):
	if s.kind!="line" or (s.closed and not s.get("closed_by_projection",false)): return
	var loop:=preload("res://cad/CADProjectedGeometry.gd").loop(s)
	s.closed=loop.size()>=3 and simple_polygon(loop)
	s.closed_by_projection=s.closed

func set_profile(id: int, kind: String, points: Array, closed: bool = true):
	if busy or sketch(id).is_empty(): return
	checkpoint()
	var s := sketch(id)
	s.kind = kind
	s.points = points.duplicate(true)
	s.closed = closed
	s.closed_by_projection=false
	s.constraints = s.get("constraints",[]).filter(func(c): return int(c.get("point",-1))<points.size() and (c.get("field")!="angle" or preload("res://cad/CADAngleDimension.gd").valid(s,c)))
	Constraints.solve(sketches)
	refresh_projected_closure(s)
	changed.emit()

static func profile(s: Dictionary) -> PackedVector2Array:
	if s.has("region_profiles"):
		var polygon:=PackedVector2Array()
		for p in s.region_profiles[0].outer:polygon.append(Vector2(p[0],p[1]))
		return polygon
	if s.get("closed_by_projection",false): return preload("res://cad/CADProjectedGeometry.gd").loop(s)
	var p := PackedVector2Array()
	for v in s.points: p.append(Vector2(v[0],v[1]))
	if s.kind == "rectangle" and p.size() == 2:
		var c := p[0]
		var half := (p[1]-c).abs()
		p = PackedVector2Array([c+Vector2(-half.x,-half.y),c+Vector2(half.x,-half.y),c+half,c+Vector2(-half.x,half.y)])
	elif s.kind == "circle" and p.size() == 2:
		var c := p[0]
		var radius := p[0].distance_to(p[1])
		p.clear()
		var segments := 96
		if radius>0.01: segments=clampi(ceili(PI/acos(clampf(1.0-0.01/radius,-1,1))/4.0)*4,96,2048)
		for i in segments: p.append(c+Vector2(cos(TAU*i/segments),sin(TAU*i/segments))*radius)
	return p

func add_angle(id: int,c: Dictionary) -> int:
	var s:=sketch(id)
	if busy or s.is_empty() or not preload("res://cad/CADAngleDimension.gd").valid(s,c): return -1
	checkpoint()
	for i in s.get("constraints",[]).size():
		var old: Dictionary=s.constraints[i]
		if old.get("field")=="angle" and int(old.vertex)==int(c.vertex) and [int(old.point),int(old.other)].has(int(c.point)) and [int(old.point),int(old.other)].has(int(c.other)):
			s.constraints[i]=c.duplicate(true);changed.emit();return i
	s.constraints.append(c.duplicate(true))
	changed.emit()
	return s.constraints.size()-1

func dimension(id: int, field: String, value: float) -> bool:
	var s := sketch(id)
	if busy or s.is_empty() or not is_finite(value) or value<=0 or value>100000 or s.points.size()<2: return false
	var parts:=field.split(":")
	var key:=parts[0]
	if key=="diameter": key="radius"; value/=2.0
	var endpoint: int=int(parts[1]) if parts.size()>1 else s.points.size()-1
	var angular:=key=="angle"
	if angular:
		if endpoint<0 or endpoint>=s.constraints.size() or s.constraints[endpoint].get("field")!="angle" or value<=0.01 or value>=179.99: return false
	if not angular and (endpoint<0 or endpoint>=s.points.size() or (s.kind=="line" and endpoint==0 and not s.closed)): return false
	if not angular and ((s.kind=="line" and key!="length") or (s.kind=="circle" and key!="radius") or (s.kind=="rectangle" and key not in ["width","height"])): return false
	var before:=snapshot()
	var old_undo:=undo_steps.duplicate(true)
	var old_redo:=redo_steps.duplicate(true)
	checkpoint()
	if angular:
		s.constraints[endpoint].value=value
	else:
		s.constraints=s.get("constraints",[]).filter(func(c): return not (c.kind=="dimension" and c.field==key and int(c.point)==endpoint))
		s.constraints.append({"kind":"dimension","field":key,"point":endpoint,"value":value})
	var registry: Dictionary={}
	for item in sketches: registry[int(item.id)]=item
	var placement:=s.duplicate(true)
	placement.constraints=placement.constraints.filter(func(c): return not (c.kind=="dimension" and c.field==key and int(c.point)==endpoint))
	var placement_registry:=registry.duplicate()
	placement_registry[int(s.id)]=placement
	var state:=SketchConstraints.state(placement,placement_registry,constraint_states())
	# Preserve the start of a free segment, but never seed a fixed endpoint.
	# For a projected anchor, solve from the valid placement and move the free side.
	if not angular and not state.points[endpoint]:
		var a:=Vector2(s.points[(endpoint+s.points.size()-1)%s.points.size()][0],s.points[(endpoint+s.points.size()-1)%s.points.size()][1])
		var b:=Vector2(s.points[endpoint][0],s.points[endpoint][1])
		if key in ["width","height","radius"]: a=Vector2(s.points[0][0],s.points[0][1])
		if key=="width": b.x=a.x+(1 if b.x>=a.x else -1)*value/2
		elif key=="height": b.y=a.y+(1 if b.y>=a.y else -1)*value/2
		else:
			var direction: Vector2=(b-a).normalized()
			if direction.is_zero_approx(): direction=Vector2.RIGHT
			b=a+direction*value
		s.points[endpoint]=[b.x,b.y]
	SketchConstraints.solve(s,registry)
	Constraints.solve(sketches)
	for item in sketches: refresh_projected_closure(item)
	var error:=0.0
	for residual in SketchConstraints.residuals(s,registry): error=maxf(error,absf(residual))
	if error>0.002 or not await rebuild_features():
		load_document(before,false)
		undo_steps=old_undo
		redo_steps=old_redo
		status.emit("Dimension conflicts with retained constraints or solid geometry.")
		return false
	changed.emit()
	return true

func edit_feature_depth(body_id: int,index: int,value: float) -> bool:
	var b:=body(body_id)
	if busy or not active_grabs.is_empty() or b.is_empty() or index<0 or index>=b.features.size() or not is_finite(value) or absf(value)<0.01 or absf(value)>100000: return false
	if is_equal_approx(float(b.features[index].depth_mm),value): return true
	var before:=snapshot()
	var old_undo:=undo_steps.duplicate(true)
	var old_redo:=redo_steps.duplicate(true)
	checkpoint()
	b.features[index].depth_mm=value
	if not await rebuild_features(body_id):
		load_document(before,false)
		undo_steps=old_undo;redo_steps=old_redo
		status.emit("Depth cannot rebuild this part. The last good solid was retained.")
		return false
	status.emit("Extrusion depth updated · %.2f mm" % value)
	return true

func place_dimension_label(id: int,field: String,offset: Vector2):
	var s:=sketch(id)
	if busy or s.is_empty() or not offset.is_finite() or absf(offset.x)>100000 or absf(offset.y)>100000: return
	var previous: Array=s.get("dimension_labels",{}).get(field,[])
	if previous==[offset.x,offset.y]: return
	checkpoint()
	if not s.has("dimension_labels"): s.dimension_labels={}
	s.dimension_labels[field]=[offset.x,offset.y]
	changed.emit()

func constraint_states() -> Dictionary:
	var registry: Dictionary={}
	var result: Dictionary={}
	for s in sketches: registry[int(s.id)]=s
	for s in Constraints.dependency_order(sketches):
		result[int(s.id)]=SketchConstraints.state(s,registry,result)
	return result

static func mesh_from_faces(faces: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for p in faces: surface.add_vertex(Vector3(p[0],p[1],p[2]))
	if faces.is_empty(): return null
	surface.generate_normals()
	return surface.commit()

static func faces_from_mesh(mesh: Mesh) -> Array:
	var a: Array = []
	for p in mesh.get_faces(): a.append([p.x,p.y,p.z])
	return a

static func volume(faces: Array) -> float:
	if faces.is_empty(): return 0.0
	# Use a local reference so room-scale millimeter coordinates do not cause
	# catastrophic cancellation in the signed tetrahedron sum.
	var origin:=Vector3(faces[0][0],faces[0][1],faces[0][2])
	var result:=0.0
	for i in range(0,faces.size(),3):
		var a:=Vector3(faces[i][0],faces[i][1],faces[i][2])-origin
		var b:=Vector3(faces[i+1][0],faces[i+1][1],faces[i+1][2])-origin
		var c:=Vector3(faces[i+2][0],faces[i+2][1],faces[i+2][2])-origin
		result+=a.dot(b.cross(c))/6.0
	return absf(result)

func extrude(id: int, depth_mm: float, operation: String, target_id: int = -1,definition: Dictionary={}) -> bool:
	var s: Dictionary=definition if not definition.is_empty() else sketch(id)
	if busy or s.is_empty(): return false
	if not s.closed or absf(depth_mm) < 0.01 or absf(depth_mm)>100000 or not is_finite(depth_mm):
		status.emit("Close a profile and enter a nonzero depth (mm).")
		return false
	if s.has("region_profiles"):
		var combined: Dictionary=load("res://cad/CADSketchRegions.gd").solid_regions(load("res://cad/CADSketchRegions.gd").unpacked(s.region_profiles))
		if not combined.error.is_empty():
			status.emit("Extrusion cannot make a printable part. "+combined.error)
			return false
	var polygon := profile(s)
	if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty() or not simple_polygon(polygon):
		status.emit("Use a closed profile without crossing or overlapping lines.")
		return false
	if operation not in ["New","Add","Remove"]: return false
	var target := body(target_id if target_id>=0 else int(s.body_id))
	if operation != "New" and target.is_empty():
		status.emit("Select a body and sketch on its face for Add or Remove.")
		return false
	# A boundary-only contact has no volume to subtract. Reject it before CSG
	# can turn a roundoff sliver at the sketch face into stray surface triangles.
	if operation=="Remove" and removal_overlap_depth(s,target,depth_mm)<=0.002:
		status.emit("Remove points outside the part. Reverse direction to cut inward; the part is unchanged.")
		return false
	busy = true
	changed.emit()
	var extrusion: CSGShape3D=extrusion_tool(s,depth_mm,operation,target)
	var root: CSGShape3D=extrusion
	if operation!="New":
		var base:=CSGMesh3D.new()
		base.mesh=mesh_from_faces(target.faces)
		extrusion.operation=CSGShape3D.OPERATION_UNION if operation=="Add" else CSGShape3D.OPERATION_SUBTRACTION
		base.add_child(extrusion)
		root=base
	root.visible = false
	add_child(root)
	# Godot CSG is deferred. Never export an old or incomplete boolean result.
	await get_tree().process_frame
	await get_tree().process_frame
	var mesh := root.bake_static_mesh()
	root.queue_free()
	busy = false
	if mesh == null or mesh.get_faces().is_empty():
		status.emit("Operation produced no solid. Check the profile and depth.")
		changed.emit()
		return false
	var faces: Array = []
	for vertex in mesh.get_faces():
		var point: Vector3 = root.transform * vertex
		faces.append([point.x,point.y,point.z])
	faces=preload("res://cad/CADSolidValidation.gd").clean_faces(faces)
	var solid_error:=preload("res://cad/CADSolidValidation.gd").error(faces)
	if not solid_error.is_empty():
		status.emit("Extrusion cannot make a printable part. "+solid_error)
		changed.emit()
		return false
	if operation=="Remove" and volume(faces)>=volume(target.faces):
		status.emit("Remove did not produce a smaller solid. Reverse direction or check the profile; the part is unchanged.")
		changed.emit()
		return false
	if operation != "New" and absf(volume(faces)-volume(target.faces)) < maxf(0.01,volume(target.faces)*0.00001):
		status.emit("The extrusion does not change the selected body. Reverse depth to cut inward.")
		changed.emit()
		return false
	checkpoint()
	var feature := {"sketch":s.duplicate(true),"depth_mm":depth_mm,"operation":operation}
	if operation == "New":
		var bid := next_id
		next_id += 1
		bodies.append({"id":bid,"name":"Part "+str(bodies.size()+1),"faces":faces,"features":[feature]})
		s.body_id = bid
	else:
		s.body_id=int(target.id)
		target.faces = faces
		target.features.append(feature)
	for entity in sketch_members(id): entity.body_id=s.body_id
	rebuild_visuals()
	status.emit(operation+" extrusion complete · "+str(depth_mm)+" mm")
	changed.emit()
	return true

static func extrusion_tool(s: Dictionary,depth: float,operation: String,target: Dictionary={}) -> CSGShape3D:
	var limits:=removal_tool_limits(s,target,depth) if operation=="Remove" else Vector2(0,depth)
	var pose:=unpack_transform(s.plane)
	pose.origin+=pose.basis.z*maxf(limits.x,limits.y)
	var length_:=absf(limits.y-limits.x)
	if not s.has("region_profiles"):
		var poly:=CSGPolygon3D.new();poly.polygon=profile(s);poly.depth=length_;poly.transform=pose
		return poly
	var root:=CSGCombiner3D.new()
	var regions: Array=load("res://cad/CADSketchRegions.gd").unpacked(s.region_profiles)
	var combined: Dictionary=load("res://cad/CADSketchRegions.gd").solid_regions(regions)
	if combined.error.is_empty():regions=combined.regions
	for region in regions:
		var poly:=CSGPolygon3D.new();poly.polygon=region.outer;poly.depth=length_;poly.transform=pose
		root.add_child(poly)
		for hole in region.holes:
			var cut:=CSGPolygon3D.new();cut.polygon=hole;cut.depth=length_+0.04;cut.position.z=0.02
			cut.operation=CSGShape3D.OPERATION_SUBTRACTION;poly.add_child(cut)
	return root

static func removal_tool_limits(s: Dictionary,target: Dictionary,depth: float) -> Vector2:
	# A cutter cap coincident with a rotated, tessellated solid face can leave
	# fragments of that face behind in CSG. Cross only those shared boundaries;
	# an interior blind-cut floor stays at the exact user-entered depth.
	var limits:=Vector2(0,depth)
	if target.is_empty(): return limits
	var inverse:=unpack_transform(s.plane).affine_inverse()
	var touches_start:=false
	var low:=INF
	var high:=-INF
	for i in range(0,target.faces.size(),3):
		var p: Array=[]
		for j in 3:
			var v: Array=target.faces[i+j]
			var local: Vector3=inverse*Vector3(v[0],v[1],v[2])
			p.append(local)
			low=minf(low,local.z);high=maxf(high,local.z)
		var normal: Vector3=(p[1]-p[0]).cross(p[2]-p[0]).normalized()
		if absf(normal.z)<0.999: continue
		if p.all(func(v):return absf(v.z)<0.002): touches_start=true
	if touches_start: limits.x-=signf(depth)*0.02
	# Extend the far cap only at the outer boundary, never into a later feature
	# beyond an internal face (which would deepen a nominally blind cut).
	if absf(depth-low)<0.002 or absf(depth-high)<0.002: limits.y+=signf(depth)*0.02
	return limits

static func removal_overlap_depth(s: Dictionary,target: Dictionary,depth: float) -> float:
	if target.is_empty(): return 0.0
	var inverse:=unpack_transform(s.plane).affine_inverse()
	var low:=INF
	var high:=-INF
	for p in target.faces:
		var z: float=(inverse*Vector3(p[0],p[1],p[2])).z
		low=minf(low,z); high=maxf(high,z)
	return maxf(0.0,minf(high,maxf(0,depth))-maxf(low,minf(0,depth)))

static func simple_polygon(p: PackedVector2Array) -> bool:
	for i in p.size():
		if p[i].distance_to(p[(i+1)%p.size()])<0.001: return false
		for j in range(i+1,p.size()):
			if j==i+1 or (i==0 and j==p.size()-1): continue
			if Geometry2D.segment_intersects_segment(p[i],p[(i+1)%p.size()],p[j],p[(j+1)%p.size()]) != null: return false
	return true

func rebuild_visuals():
	for node in get_children():
		if node.has_meta("cad_body_id"):
			node.dispose()
			remove_child(node)
		elif node is MeshInstance3D:
			remove_child(node)
			node.queue_free()
	for b in bodies:
		var points:=PackedVector3Array()
		var bounds:=AABB(Vector3(b.faces[0][0],b.faces[0][1],b.faces[0][2]),Vector3.ZERO)
		for point in b.faces: bounds=bounds.expand(Vector3(point[0],point[1],point[2]))
		var center:=bounds.get_center()
		var local_faces: Array=[]
		for point in b.faces:
			var v: Vector3=(Vector3(point[0],point[1],point[2])-center)*0.001
			local_faces.append([v.x,v.y,v.z])
			points.append(v)
		var pickable=preload("res://cad/CADPickable.gd").new()
		pickable.name="Part_"+str(b.id)
		pickable.document=self
		pickable.body_id=int(b.id)
		pickable.set_meta("cad_body_id",int(b.id))
		pickable.model_transform=Transform3D(Basis.IDENTITY,center*0.001)
		pickable.position=center*0.001
		pickable.top_level=true
		pickable.collision_layer=4
		pickable.collision_mask=7
		pickable.freeze=true
		pickable.release_mode=1
		pickable.second_hand_grab=1
		var instance=MeshInstance3D.new()
		instance.set_script(preload("res://cad/CADPartMesh.gd"))
		instance.name="MeshInstance3D"
		instance.document=self
		instance.body_id=int(b.id)
		instance.mesh=mesh_from_faces(local_faces)
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color.html(b.get("color","70cbbfff"))
		material.metallic=0.25
		material.roughness=0.38
		instance.material_override=material
		pickable.add_child(instance)
		var collision:=CollisionShape3D.new()
		collision.name="CollisionShape3D"
		var hull:=ConvexPolygonShape3D.new()
		hull.points=points
		collision.shape=hull
		pickable.add_child(collision)
		add_child(pickable)
		pickable.update_view()

func apply_body_pose(id: int, baseline: Dictionary, attached: Dictionary, delta_mm: Transform3D):
	var target:=body(id)
	if target.is_empty(): return
	for field in ["faces","base_faces"]:
		if not baseline.has(field): continue
		var points: Array=[]
		for point in baseline[field]:
			var v: Vector3=delta_mm*Vector3(point[0],point[1],point[2])
			points.append([v.x,v.y,v.z])
		target[field]=points
	target.features=baseline.features.duplicate(true)
	for feature in target.features:
		feature.sketch.plane=pack_transform(delta_mm*unpack_transform(feature.sketch.plane))
		for entity in feature.sketch.get("region_entities",[]):entity.plane=pack_transform(delta_mm*unpack_transform(entity.plane))
	for sid in attached:
		var current:=sketch(int(sid))
		if not current.is_empty(): current.plane=pack_transform(delta_mm*unpack_transform(attached[sid].plane))

func load_document(data: Dictionary, reset_history: bool = true):
	active_grabs.clear()
	busy=false
	reference_plane=data.get("reference_plane",{}).duplicate(true)
	deleted_conversions=data.get("deleted_conversions",[]).duplicate()
	bodies = data.bodies.duplicate(true)
	sketches = data.sketches.duplicate(true)
	next_id = int(data.next_id)
	var o: Array = data.get("origin_mm",[0,1150,-650])
	origin_mm=Vector3(o[0],o[1],o[2])
	origin_yaw=float(data.get("origin_yaw",0.0))
	if reset_history:
		undo_steps.clear()
		redo_steps.clear()
	rebuild_visuals()
	changed.emit()

static func valid_region_definition(profile: Dictionary) -> bool:
	if profile.has("region_anchor") and not valid_vector(profile.region_anchor,2):return false
	if not load("res://cad/CADSketchRegions.gd").valid(profile.get("region_profiles")):return false
	var ids=profile.get("region_ids")
	var entities=profile.get("region_entities")
	if not ids is Array or ids.size()!=profile.region_profiles.size() or not entities is Array or entities.is_empty() or entities.size()>1000:return false
	var seen: Dictionary={}
	for id in ids:
		if not id is String or id.is_empty() or id.length()>128 or seen.has(id):return false
		seen[id]=true
	for entity in entities:
		if not entity is Dictionary or entity.get("kind") not in ["line","circle","rectangle"] or not entity.get("closed") is bool or not entity.get("points") is Array:return false
		if not (entity.get("id") is int or entity.get("id") is float) or not is_finite(float(entity.id)):return false
		if not valid_vector(entity.get("plane"),12) or entity.plane!=profile.plane or entity.points.size()>10000:return false
		if not preload("res://cad/CADProjectedGeometry.gd").valid(entity):return false
		for point in entity.points:
			if not valid_vector(point,2):return false
	return true

static func validate(data: Variant) -> String:
	if not data is Dictionary or data.get("version") != 1 or not data.get("bodies") is Array or not data.get("sketches") is Array or not data.get("next_id") is float and not data.get("next_id") is int:
		return "Invalid CAD document."
	if data.has("origin_mm") and not valid_vector(data.origin_mm,3): return "Invalid CAD origin."
	if data.has("origin_yaw"):
		if not (data.origin_yaw is int or data.origin_yaw is float) or not is_finite(float(data.origin_yaw)) or absf(float(data.origin_yaw))>PI+0.000001: return "Invalid CAD origin heading."
	if data.has("deleted_conversions"):
		if not data.deleted_conversions is Array: return "Invalid deleted conversion history."
		for id in data.deleted_conversions:
			if not (id is int or id is float) or not is_finite(float(id)) or int(id)<0 or int(id)>=int(data.next_id): return "Invalid deleted conversion identifier."
	if data.has("reference_plane"):
		var ref: Variant=data.reference_plane
		if not ref is Dictionary or not valid_vector(ref.get("plane_mm"),12) or not valid_vector(ref.get("stage_pose"),12) or not ref.get("locked") is bool or not ref.get("lock_rotation",false) is bool: return "Invalid reference plane."
		for key in ["plane_mm","stage_pose"]:
			var basis: Basis=unpack_transform(ref[key]).basis
			if not basis.is_equal_approx(basis.orthonormalized()) or basis.determinant()<0.99: return "Invalid reference plane rotation."
	var ids := {}
	for b in data.bodies:
		if not b is Dictionary or not b.get("id") is float and not b.get("id") is int or not b.get("name") is String or not b.get("faces") is Array or not b.get("features") is Array: return "Invalid CAD body."
		if ids.has(b.id) or b.faces.is_empty() or b.faces.size()%3!=0 or b.faces.size()>300000: return "Invalid CAD solid."
		ids[b.id] = true
		if b.has("color") and (not b.color is String or not Color.html_is_valid(b.color)): return "Invalid CAD color."
		if b.features.size()>250: return "Too many CAD features."
		for i in b.features.size():
			if not b.features[i] is Dictionary: return "Invalid solid feature."
			if b.features[i].get("operation")=="New" and (i!=0 or b.has("base_faces")): return "Invalid solid feature order."
		if b.has("base_faces"):
			if not b.base_faces is Array or b.base_faces.is_empty() or b.base_faces.size()%3!=0: return "Invalid CAD base mesh."
			for v in b.base_faces:
				if not valid_vector(v,3): return "Invalid CAD base vertex."
		for feature in b.features:
			if not feature is Dictionary or feature.get("operation") not in ["New","Add","Remove"] or not (feature.get("depth_mm") is int or feature.get("depth_mm") is float): return "Invalid solid feature."
			if not is_finite(float(feature.depth_mm)) or absf(float(feature.depth_mm))<0.01 or absf(float(feature.depth_mm))>100000: return "Invalid feature depth."
			var profile: Variant=feature.get("sketch")
			if not profile is Dictionary or not (profile.get("id") is int or profile.get("id") is float) or profile.get("kind") not in ["line","rectangle","circle"] or not profile.get("points") is Array or not valid_vector(profile.get("plane"),12): return "Invalid feature sketch."
			if profile.has("region_profiles"):
				if not valid_region_definition(profile):return "Invalid solid region definition."
			if not preload("res://cad/CADProjectedGeometry.gd").valid(profile): return "Invalid projected feature edges."
			if profile.points.size()>10000 or (profile.points.size()<2 and not (profile.has("region_profiles") or profile.get("closed_by_projection",false) and preload("res://cad/CADProjectedGeometry.gd").loop(profile).size()>=3)): return "Invalid feature profile."
			for point in profile.points:
				if not valid_vector(point,2): return "Invalid feature point."
		if b.has("converted_source"):
			var source: Variant=b.converted_source
			if not source is Dictionary or source.get("shape") not in ["cube","brick","wedge","m_cube","corner_wedge"] or not valid_vector(source.get("transform"),12) or not valid_vector(source.get("grid"),3) or not source.get("color") is String or not Color.html_is_valid(source.color): return "Invalid block conversion source."
			if not source.get("cells",[]) is Array: return "Invalid converted cells."
			for cell in source.get("cells",[]):
				if not valid_vector(cell,3): return "Invalid converted cell."
		for v in b.faces:
			if not valid_vector(v,3): return "Invalid CAD vertex."
	for s in data.sketches:
		if not s is Dictionary or not s.get("id") is float and not s.get("id") is int or ids.has(s.get("id")) or not s.get("body_id") is float and not s.get("body_id") is int: return "Invalid sketch ID."
		ids[s.id] = true
		if s.get("kind") not in ["line","rectangle","circle"] or not s.get("closed") is bool or not s.get("points") is Array or not valid_vector(s.get("plane"),12): return "Invalid sketch."
		if s.has("dimension_labels"):
			if not s.dimension_labels is Dictionary or s.dimension_labels.size()>10000: return "Invalid dimension label positions."
			for field in s.dimension_labels:
				if not field is String or not valid_vector(s.dimension_labels[field],2): return "Invalid dimension label position."
		if not preload("res://cad/CADProjectedGeometry.gd").valid(s): return "Invalid projected sketch edges."
		if s.points.size()>10000: return "Sketch too large."
		for p in s.points:
			if not valid_vector(p,2): return "Invalid sketch point."
		if not unpack_transform(s.plane).basis.is_equal_approx(unpack_transform(s.plane).basis.orthonormalized()): return "Invalid sketch plane."
	var sketch_ids := {}
	for item in data.sketches: sketch_ids[int(item.id)]=item
	for item in data.sketches:
		if item.has("group_id"):
			if not (item.group_id is int or item.group_id is float) or float(item.group_id)!=int(item.group_id):return "Invalid sketch group."
			var root: Dictionary=sketch_ids.get(int(item.group_id),{})
			if root.is_empty() or root.has("group_id") or int(item.group_id)==int(item.id) or root.plane!=item.plane:return "Invalid sketch group reference."
		if not item.get("constraints",[]) is Array: return "Invalid sketch constraints."
		for c in item.get("constraints",[]):
			if not c is Dictionary or c.get("kind") not in ["origin","coincident","midpoint","horizontal","vertical","vertical_align","horizontal_align","projected_point","projected_center","parallel","perpendicular","equal","tangent","dimension"]: return "Unknown sketch constraint."
			if not (c.get("point") is int or c.get("point") is float): return "Invalid constraint point."
			if int(c.point)<0 or int(c.point)>=item.points.size(): return "Invalid constraint point."
			if c.kind=="dimension":
				if c.get("field") not in ["length","width","height","radius","angle"] or not (c.get("value") is int or c.get("value") is float) or not is_finite(float(c.value)) or float(c.value)<=0 or float(c.value)>100000: return "Invalid driving dimension."
				if c.field=="angle":
					if not preload("res://cad/CADAngleDimension.gd").valid(item,c): return "Invalid angle dimension."
					continue
				if (item.kind=="line" and c.field!="length") or (item.kind=="circle" and c.field!="radius") or (item.kind=="rectangle" and c.field not in ["width","height"]): return "Invalid driving dimension type."
				if item.points.size()<2 or (item.kind!="line" and int(c.point)!=1) or (item.kind=="line" and int(c.point)==0 and not item.closed): return "Invalid dimension segment."
				continue
			if c.kind in ["origin","horizontal","vertical"]: continue
			if not (c.get("target") is int or c.get("target") is float) or not (c.get("index",0) is int or c.get("index",0) is float): return "Invalid constraint reference."
			var target: Dictionary=sketch_ids.get(int(c.target),{})
			if c.kind=="projected_center":
				if target.is_empty() or int(c.get("index",0))<0 or int(c.get("index",0))>=target.get("projected_centers",[]).size(): return "Missing projected center reference."
				continue
			if c.kind=="projected_point":
				if target.is_empty() or int(c.get("index",0))<0 or int(c.get("index",0))>=target.get("projected_edges",[]).size(): return "Missing projected edge reference."
				if not (c.get("t") is int or c.get("t") is float) or not is_finite(float(c.t)) or float(c.t)<0 or float(c.t)>1: return "Invalid projected edge point."
				continue
			if target.is_empty() or int(c.get("index",0))<0 or int(c.get("index",0))>=target.points.size(): return "Missing constraint reference."
			if int(c.target)==int(item.id) and int(c.get("index",0))>=int(c.point): return "Cyclic sketch constraint."
	if Constraints.dependency_order(data.sketches).size()!=data.sketches.size(): return "Cyclic sketch constraints."
	for id in ids:
		if int(id)>=int(data.next_id): return "Invalid next CAD identifier."
	return ""

static func valid_vector(v: Variant, count: int) -> bool:
	if not v is Array or v.size()!=count: return false
	for n in v:
		if not (n is int or n is float) or not is_finite(float(n)) or absf(float(n))>10000000: return false
	return true

func infer_point(id: int, point: Vector2, tolerance: float) -> Dictionary:
	var s := sketch(id)
	if s.is_empty(): return {"point":point,"constraint":{},"label":""}
	return Constraints.infer(sketches,s,point,tolerance)

func add_inference(id: int, index: int, constraint: Dictionary):
	var s := sketch(id)
	if constraint.is_empty() or s.is_empty(): return
	if constraint.get("kind") not in ["projected_point","projected_center"] and constraint.get("target",-1)==id and int(constraint.get("index",-1))>=index: return
	var c := constraint.duplicate(true)
	var additional: Array=c.get("also",[])
	c.erase("also")
	c.point=index
	if not s.has("constraints"): s.constraints=[]
	s.constraints.append(c)
	if not validate(snapshot()).is_empty():
		s.constraints.pop_back()
		status.emit("That constraint would create a conflicting dependency.")
		return
	Constraints.solve(sketches)
	for extra in additional: add_inference(id,index,extra)
	refresh_projected_closure(s)
	changed.emit()

func clear_constraints(id: int):
	var s := sketch(id)
	if s.is_empty(): return
	checkpoint()
	for entity in sketch_members(id):entity.constraints=[]
	changed.emit()

func move_origin(position_mm: Vector3, record: bool = true, yaw: float = NAN):
	if busy: return
	if record: checkpoint()
	var delta := position_mm-origin_mm
	for b in bodies:
		for i in b.faces.size():
			var p: Array = b.faces[i]
			b.faces[i]=[p[0]+delta.x,p[1]+delta.y,p[2]+delta.z]
		if b.has("base_faces"):
			for i in b.base_faces.size():
				var p: Array=b.base_faces[i]
				b.base_faces[i]=[p[0]+delta.x,p[1]+delta.y,p[2]+delta.z]
		for feature in b.features:
			if feature.has("sketch"):
				for i in 3: feature.sketch.plane[9+i]+=delta[i]
				for entity in feature.sketch.get("region_entities",[]):
					for i in 3:entity.plane[9+i]+=delta[i]
	for s in sketches:
		for i in 3: s.plane[9+i]+=delta[i]
	origin_mm=position_mm
	if is_finite(yaw): origin_yaw=wrapf(yaw,-PI,PI)
	rebuild_visuals()
	changed.emit()

func base_plane(name: String) -> Transform3D:
	var basis := Basis.IDENTITY
	if name=="Top": basis=Basis(Vector3.RIGHT,Vector3.FORWARD,Vector3.UP)
	elif name=="Right": basis=Basis(Vector3.FORWARD,Vector3.UP,Vector3.RIGHT)
	return Transform3D(Basis(Vector3.UP,origin_yaw)*basis,origin_mm)

func rebuild_features(force_body: int=-1) -> bool:
	# Replay only changed bodies; keep the last good mesh until every feature succeeds.
	var updates := {}
	busy=true
	changed.emit()
	for b in bodies:
		var features: Array=b.features.duplicate(true)
		var modified: bool=int(b.id)==force_body
		for feature in features:
			var current:=sketch(int(feature.sketch.id))
			if current.is_empty(): continue
			if feature.sketch.has("region_entities"):
				if entity_geometry(feature.sketch.region_entities)!=entity_geometry(sketch_members(int(current.id))):
					var bundle:=region_profile(int(current.id),feature.sketch.region_ids)
					if bundle.is_empty():busy=false;changed.emit();return false
					feature.sketch=bundle;modified=true
				continue
			if feature.sketch.points!=current.points or feature.sketch.plane!=current.plane or feature.sketch.get("projected_edges",[])!=current.get("projected_edges",[]):
				feature.sketch=current.duplicate(true)
				modified=true
		if not modified: continue
		var evaluator=get_script().new()
		add_child(evaluator)
		evaluator.remove_from_group("cad_document")
		evaluator.visible=false
		evaluator.next_id=1000000
		if b.has("base_faces"):
			evaluator.bodies=[{"id":0,"name":"Base","faces":b.base_faces.duplicate(true),"features":[]}]
		var succeeded:=true
		for feature in features:
			var profile: Dictionary=feature.sketch.duplicate(true)
			profile.body_id=int(evaluator.bodies[0].id) if not evaluator.bodies.is_empty() else -1
			evaluator.sketches=[profile]
			if not await evaluator.extrude(int(profile.id),float(feature.depth_mm),feature.operation):
				succeeded=false
				break
		if succeeded and not evaluator.bodies.is_empty(): updates[int(b.id)]={"faces":evaluator.bodies[0].faces.duplicate(true),"features":features}
		evaluator.queue_free()
		if not succeeded:
			busy=false
			changed.emit()
			return false
	for b in bodies:
		if updates.has(int(b.id)):
			b.faces=updates[int(b.id)].faces
			b.features=updates[int(b.id)].features
	busy=false
	rebuild_visuals()
	changed.emit()
	return true

func set_view_transform(value: Transform3D):
	view_transform=value
	for child in get_children():
		if child.has_meta("cad_body_id") and not child.is_picked_up(): child.update_view()

func set_reference_plane(value: Dictionary):
	if busy: return
	checkpoint()
	reference_plane=value.duplicate(true)
	changed.emit()

func export_frame_mm() -> Transform3D:
	return unpack_transform(reference_plane.plane_mm).affine_inverse() if not reference_plane.is_empty() else Transform3D.IDENTITY

func export_faces(faces: Array) -> Array:
	if reference_plane.is_empty(): return faces
	var frame:=export_frame_mm()
	var result: Array=[]
	for point in faces:
		var p: Vector3=frame*Vector3(point[0],point[1],point[2])
		result.append([p.x,p.y,p.z])
	return result


func print_frame_mm(body_id: int=-1) -> Transform3D:
	# An explicitly calibrated print/table plane takes precedence. Otherwise
	# remove the CAD part's placement using its original feature sketch frame.
	if not reference_plane.is_empty(): return export_frame_mm()
	var target:=body(body_id)
	if target.is_empty() and not bodies.is_empty(): target=bodies[0]
	if not target.is_empty() and not target.get("features",[]).is_empty():
		return unpack_transform(target.features[0].sketch.plane).affine_inverse()
	# Ground-aligned fallback: Godot Y-up to right-handed STL Z-up.
	return Transform3D(Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN),Vector3.ZERO)

static func print_ready_faces(faces: Array,frame: Transform3D) -> Array:
	if faces.is_empty(): return []
	var result: Array=[]
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	for p in faces:
		var point: Vector3=frame*Vector3(p[0],p[1],p[2])
		low=low.min(point);high=high.max(point)
		result.append([point.x,point.y,point.z])
	var shift:=Vector3((low.x+high.x)*0.5,(low.y+high.y)*0.5,low.z)
	for p in result:
		p[0]-=shift.x;p[1]-=shift.y;p[2]-=shift.z
	return result

func print_export_faces(body_id: int) -> Array:
	var target:=body(body_id)
	if target.is_empty(): return []
	return print_ready_faces(target.faces,print_frame_mm(body_id))
