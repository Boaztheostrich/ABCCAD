extends Node
## True stepped cross-section geometry, kept separate from the CAD/export mesh.
## Each 0.2 mm slab uses a mid-height section. Even/odd scanline filling retains
## holes and disconnected islands without requiring an external slicer library.
signal progress_changed(value: float)
var progress:=0.0
var generation:=0
var error:=""
const MAX_LAYERS=2500
const MAX_VERTICES=1800000

func cancel():
	generation+=1

func build(faces: Array, print_plane_mm: Transform3D, layer_height: float=0.2) -> ArrayMesh:
	generation+=1
	var token:=generation
	error=""
	progress=0.0
	progress_changed.emit(progress)
	if faces.is_empty() or layer_height<0.01: error="No solid to preview."; return null
	var inverse:=print_plane_mm.affine_inverse()
	var local:=PackedVector3Array()
	var low:=INF
	var high:=-INF
	for p in faces:
		var v: Vector3=inverse*Vector3(p[0],p[1],p[2])
		local.append(v)
		low=minf(low,v.z)
		high=maxf(high,v.z)
	var layers:=ceili((high-low)/layer_height-0.0001)
	if layers<1 or layers>MAX_LAYERS:
		error="Preview supports up to 500 mm height at 0.2 mm layers."
		return null
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	var budget:=Time.get_ticks_msec()
	var previous: Array=[]
	var previous_key: Array=[]
	await get_tree().process_frame # Let the circular loader paint before work.
	for layer in layers:
		if token!=generation or not is_inside_tree(): return null
		var bottom:=low+layer*layer_height
		var top:=minf(high,bottom+layer_height)
		var segments:=section(local,(bottom+top)*0.5)
		append_walls(vertices,colors,segments,bottom,top,layer)
		var key:=section_key(segments)
		if key!=previous_key: append_boundary(vertices,colors,previous,segments,bottom)
		if layer==layers-1: append_boundary(vertices,colors,segments,[],top)
		previous=segments
		previous_key=key
		if vertices.size()>MAX_VERTICES:
			error="Preview is too detailed; use a smaller part."
			return null
		progress=float(layer+1)/layers*0.95
		if Time.get_ticks_msec()-budget>=8:
			progress_changed.emit(progress)
			await get_tree().process_frame
			budget=Time.get_ticks_msec()
	if token!=generation: return null
	if vertices.is_empty(): error="Could not section this solid."; return null
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in vertices.size():
		if i%3==0:
			# Calculate flat normals before converting mm into room-space meters.
			# Thin layer triangles otherwise amplify meter-space float roundoff.
			var normal: Vector3=-(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).normalized()
			surface.set_normal((print_plane_mm.basis*normal).normalized())
		surface.set_color(colors[i])
		surface.add_vertex(print_plane_mm*vertices[i]*0.001)
		if i%12000==0 and Time.get_ticks_msec()-budget>=8:
			if token!=generation: return null
			progress=0.95+0.04*float(i)/vertices.size()
			progress_changed.emit(progress)
			await get_tree().process_frame
			budget=Time.get_ticks_msec()
	var mesh:=surface.commit()
	progress=1.0
	progress_changed.emit(progress)
	return mesh

static func section(faces: PackedVector3Array, z: float) -> Array:
	var segments: Array=[]
	for i in range(0,faces.size(),3):
		var hits: Array[Vector2]=[]
		for j in 3:
			var a: Vector3=faces[i+j]
			var b: Vector3=faces[i+(j+1)%3]
			if (a.z<=z and b.z>z) or (b.z<=z and a.z>z):
				var p:=a.lerp(b,(z-a.z)/(b.z-a.z))
				var v:=Vector2(p.x,p.y)
				if hits.is_empty() or v.distance_to(hits[0])>0.00001: hits.append(v)
		if hits.size()!=2 or hits[0].distance_to(hits[1])<0.00001: continue
		var normal: Vector3=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i])
		var d: Vector2=hits[1]-hits[0]
		if Vector2(d.y,-d.x).dot(Vector2(normal.x,normal.y))<0:
			segments.append([hits[1],hits[0]])
		else: segments.append([hits[0],hits[1]])
	return simplify_section(segments)

static func triangle(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3,b: Vector3,c: Vector3,color: Color):
	if (b-a).cross(c-a).length_squared()<0.0000000001: return
	vertices.append(a);vertices.append(b);vertices.append(c)
	colors.append(color);colors.append(color);colors.append(color)

static func x_at(edge: Array,y: float) -> float:
	var a: Vector2=edge[0]
	var b: Vector2=edge[1]
	return lerpf(a.x,b.x,clampf((y-a.y)/(b.y-a.y),0,1))

static func append_walls(vertices: PackedVector3Array,colors: PackedColorArray,segments: Array,bottom: float,top: float,index: int):
	var wall:=Color(0.83,0.87,0.92) if index%2==0 else Color(0.76,0.81,0.87)
	for edge in segments:
		var a: Vector2=edge[0]
		var b: Vector2=edge[1]
		var p:=Vector3(a.x,a.y,bottom)
		var q:=Vector3(b.x,b.y,bottom)
		var r:=Vector3(b.x,b.y,top)
		var s:=Vector3(a.x,a.y,top)
		triangle(vertices,colors,p,q,r,wall)
		triangle(vertices,colors,p,r,s,wall)

static func append_slab(vertices: PackedVector3Array,colors: PackedColorArray,segments: Array,bottom: float,top: float,index: int):
	append_walls(vertices,colors,segments,bottom,top,index)
	append_boundary(vertices,colors,[],segments,bottom)
	append_boundary(vertices,colors,segments,[],top)

static func point_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x*10000),roundi(p.y*10000))

static func section_key(segments: Array) -> Array:
	var key: Array=[]
	for edge in segments: key.append(str(point_key(edge[0]))+"/"+str(point_key(edge[1])))
	key.sort()
	return key

static func collinear(a: Vector2,b: Vector2,c: Vector2) -> bool:
	var first:=b-a
	var second:=c-b
	return absf(first.cross(second))<=0.00001*first.length()*second.length() and first.dot(second)>0

static func simplify_section(segments: Array) -> Array:
	# Triangle fans split a straight section edge into many segments. Join them
	# before building layers, keeping real corners, holes and disconnected loops.
	var by_start: Dictionary={}
	for i in segments.size():
		var key:=point_key(segments[i][0])
		if by_start.has(key): return segments
		by_start[key]=i
	var used: Dictionary={}
	var result: Array=[]
	for start in segments.size():
		if used.has(start): continue
		var loop: Array[Vector2]=[]
		var current:=start
		while not used.has(current):
			used[current]=true
			var p: Vector2=segments[current][0]
			while loop.size()>=2 and collinear(loop[-2],loop[-1],p): loop.pop_back()
			loop.append(p)
			var end:=point_key(segments[current][1])
			if not by_start.has(end): return segments
			current=int(by_start[end])
		if current!=start or loop.size()<3: return segments
		while loop.size()>3 and collinear(loop[-2],loop[-1],loop[0]): loop.pop_back()
		while loop.size()>3 and collinear(loop[-1],loop[0],loop[1]): loop.pop_front()
		for i in loop.size(): result.append([loop[i],loop[(i+1)%loop.size()]])
	return result

static func append_boundary(vertices: PackedVector3Array,colors: PackedColorArray,below: Array,above: Array,z: float):
	# Emit only the exposed difference between consecutive sections. Equal
	# interiors have no faces, eliminating coplanar internal caps / z-fighting.
	var levels: Array[float]=[]
	for edge in below+above:
		levels.append(edge[0].y)
		levels.append(edge[1].y)
	# Split scan strips where edges change order, including crossing sections.
	for first in below:
		var a: Vector2=first[0]
		var b: Vector2=first[1]
		for second in above:
			var c: Vector2=second[0]
			var d: Vector2=second[1]
			if maxf(a.x,b.x)<minf(c.x,d.x) or maxf(c.x,d.x)<minf(a.x,b.x) or maxf(a.y,b.y)<minf(c.y,d.y) or maxf(c.y,d.y)<minf(a.y,b.y): continue
			var direction:=b-a
			var other:=d-c
			var denominator:=direction.cross(other)
			if absf(denominator)<0.0000001: continue
			var t: float=(c-a).cross(other)/denominator
			var u: float=(c-a).cross(direction)/denominator
			if t>0 and t<1 and u>0 and u<1: levels.append(a.y+t*direction.y)
	levels.sort()
	var unique: Array[float]=[]
	for y in levels:
		if unique.is_empty() or y-unique[-1]>0.00001: unique.append(y)
	var cap:=Color(0.95,0.97,1.0)
	for i in range(unique.size()-1):
		var y0:=unique[i]
		var y1:=unique[i+1]
		var middle:=(y0+y1)*0.5
		var crossings: Array=[]
		for source in 2:
			for edge in (below if source==0 else above):
				if middle>minf(edge[0].y,edge[1].y) and middle<maxf(edge[0].y,edge[1].y): crossings.append({"x":x_at(edge,middle),"edge":edge,"source":source})
		crossings.sort_custom(func(a,b): return a.x<b.x)
		var inside: Array[bool]=[false,false]
		for pair in range(crossings.size()-1):
			var source: int=crossings[pair].source
			inside[source]=not inside[source]
			if inside[0]==inside[1]: continue
			var left: Array=crossings[pair].edge
			var right: Array=crossings[pair+1].edge
			var p:=Vector3(x_at(left,y0),y0,z)
			var q:=Vector3(x_at(right,y0),y0,z)
			var r:=Vector3(x_at(right,y1),y1,z)
			var s:=Vector3(x_at(left,y1),y1,z)
			if inside[0]:
				triangle(vertices,colors,p,r,q,cap)
				triangle(vertices,colors,p,s,r,cap)
			else:
				triangle(vertices,colors,p,q,r,cap)
				triangle(vertices,colors,p,r,s,cap)
