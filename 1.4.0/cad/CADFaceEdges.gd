extends RefCounted
## Boundary segments of the selected plane; shared triangulation edges vanish.
static func boundary(hit: Dictionary) -> Array:
	var edges: Dictionary={}
	var faces: Array=hit.source.faces
	var normal: Vector3=hit.normal
	var origin: Vector3=hit.point_mm
	for i in range(0,faces.size(),3):
		var points: Array=[]
		for j in 3: points.append(Vector3(faces[i+j][0],faces[i+j][1],faces[i+j][2]))
		if points.any(func(p): return absf(normal.dot(p-origin))>0.02): continue
		if absf((points[1]-points[0]).cross(points[2]-points[0]).normalized().dot(normal))<0.999: continue
		for j in 3:
			var a: Vector3=points[j];var b: Vector3=points[(j+1)%3]
			var ka: String="%.3f,%.3f,%.3f" % [a.x,a.y,a.z]
			var kb: String="%.3f,%.3f,%.3f" % [b.x,b.y,b.z]
			var key:=ka+"/"+kb if ka<kb else kb+"/"+ka
			if not edges.has(key): edges[key]={"count":0,"a":a,"b":b}
			edges[key].count+=1
	var result: Array=[]
	for edge in edges.values():
		if edge.count==1: result.append([edge.a,edge.b])
	return result

# Mesh chords on a circular rim represent one selectable CAD edge. Other
# boundaries (including polygon corners) remain individually selectable.
static func projection_group(edges: Array,chosen: Array) -> Array:
	var remaining:=edges.duplicate()
	var group: Array=[]
	var vertices: Array=[chosen[0]]
	var current: Vector2=chosen[0]
	var closed:=false
	while group.size()<edges.size():
		var found:=-1
		var next:=Vector2.ZERO
		for i in remaining.size():
			if current.distance_to(remaining[i][0])<0.002: found=i;next=remaining[i][1];break
			if current.distance_to(remaining[i][1])<0.002: found=i;next=remaining[i][0];break
		if found<0: return [chosen]
		group.append(remaining[found]);remaining.remove_at(found)
		if next.distance_to(vertices[0])<0.002: closed=true;break
		vertices.append(next);current=next
	if group.size()<32 or not closed: return [chosen]
	var a: Vector2=vertices[0]
	var b: Vector2=vertices[vertices.size()/3]-a
	var c: Vector2=vertices[vertices.size()*2/3]-a
	var cross:=b.cross(c)
	if absf(cross)<0.000001: return [chosen]
	var center:=a+Vector2(c.y*b.length_squared()-b.y*c.length_squared(),b.x*c.length_squared()-c.x*b.length_squared())/(2*cross)
	var radius:=a.distance_to(center)
	for vertex in vertices:
		if absf(vertex.distance_to(center)-radius)>0.02: return [chosen]
	return group

static func circle_center(edges: Array) -> Dictionary:
	if edges.size()<32: return {}
	var local: Array=[]
	for edge in edges: local.append([Vector2(edge[0][0],edge[0][1]),Vector2(edge[1][0],edge[1][1])])
	var group:=projection_group(local,local[0])
	if group.size()!=edges.size(): return {}
	var a: Vector2=group[0][0]
	var b: Vector2=group[group.size()/3][0]-a
	var c: Vector2=group[group.size()*2/3][0]-a
	var cross:=b.cross(c)
	if absf(cross)<0.000001: return {}
	var center:=a+Vector2(c.y*b.length_squared()-b.y*c.length_squared(),b.x*c.length_squared()-c.x*b.length_squared())/(2*cross)
	return {"center":center,"radius":a.distance_to(center)}
