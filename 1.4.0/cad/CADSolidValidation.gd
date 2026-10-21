extends RefCounted
## Check the topology of one part, including disconnected closed shells.
## CSG can leave T junctions: split unmatched edges for validation only, without
## moving vertices or changing the model/export triangles. Coordinates are mm.
const EPS := 0.0001
const CONTACT_MESSAGE := "Areas meet only at an edge or point. Add a solid bridge or extrude them as separate parts."
const OPEN_MESSAGE := "The part has an open or inconsistent surface. Edit the sketch or recreate the affected feature before exporting."

static func error(faces: Array) -> String:
	if faces.is_empty() or faces.size()%3!=0: return OPEN_MESSAGE
	var vertices: Array[Vector3]=[]
	var ids: Dictionary={}
	var edges: Dictionary={}
	for i in range(0,faces.size(),3):
		var tri: Array[int]=[]
		for j in 3:
			var p:=Vector3(faces[i+j][0],faces[i+j][1],faces[i+j][2])
			if not p.is_finite(): return OPEN_MESSAGE
			var key:=Vector3i(roundi(float(p.x)/EPS),roundi(float(p.y)/EPS),roundi(float(p.z)/EPS))
			if not ids.has(key): ids[key]=vertices.size();vertices.append(p)
			tri.append(ids[key])
		if tri[0]==tri[1] or tri[1]==tri[2] or tri[2]==tri[0]: return OPEN_MESSAGE
		for j in 3: add_edge(edges,tri[j],tri[(j+1)%3],i/3)
	var unmatched: Array=[]
	for key in edges:
		var uses: Array=edges[key]
		if uses.size()>2: return CONTACT_MESSAGE
		if uses.size()==1: unmatched.append(key)
	# Only boundary edges need refinement for the T junctions produced by CSG.
	# Sort coordinates once and scan the dominant-axis interval, not every vertex.
	if not unmatched.is_empty():
		var boundary_uses: Dictionary={}
		for key in unmatched:
			boundary_uses[key]=edges[key][0]
			edges.erase(key)
		var sorted: Array=[]
		for axis in 3:
			var order: Array=range(vertices.size())
			order.sort_custom(func(a,b):return vertices[a][axis]<vertices[b][axis])
			sorted.append(order)
		for key in unmatched:
			var a: Vector3=vertices[key.x];var b: Vector3=vertices[key.y]
			var delta:=b-a;var length_squared:=delta.length_squared()
			var axis:=delta.abs().max_axis_index()
			var order: Array=sorted[axis]
			var low:=minf(a[axis],b[axis])-EPS;var high:=maxf(a[axis],b[axis])+EPS
			var begin:=0;var end:=order.size()
			while begin<end:
				var mid: int=(begin+end)/2
				if vertices[order[mid]][axis]<low:begin=mid+1
				else:end=mid
			var cuts: Array=[{"id":key.x,"t":0.0},{"id":key.y,"t":1.0}]
			for index in range(begin,order.size()):
				var id: int=order[index];var p: Vector3=vertices[id]
				if p[axis]>high:break
				if id==key.x or id==key.y:continue
				var t:=delta.dot(p-a)/length_squared
				if t>0.0 and t<1.0 and p.distance_squared_to(a+delta*t)<=EPS*EPS:
					cuts.append({"id":id,"t":t})
			cuts.sort_custom(func(x,y):return x.t<y.t)
			var use: Vector2i=boundary_uses[key]
			for index in cuts.size()-1:
				var x: int=cuts[index].id;var y: int=cuts[index+1].id
				add_edge(edges,x if use.y==1 else y,y if use.y==1 else x,use.x)
	var fans: Dictionary={}
	for key in edges:
		var uses: Array=edges[key]
		if uses.size()>2:return CONTACT_MESSAGE
		if uses.size()!=2 or uses[0].y==uses[1].y:return OPEN_MESSAGE
		for vertex in [key.x,key.y]:
			if not fans.has(vertex):fans[vertex]={}
			var parents: Dictionary=fans[vertex]
			var a: int=uses[0].x;var b: int=uses[1].x
			if not parents.has(a):parents[a]=a
			if not parents.has(b):parents[b]=b
			parents[root(parents,a)]=root(parents,b)
	# Two otherwise closed shells touching at just a vertex have two surface
	# fans there, even though every edge still has exactly two incident faces.
	for parents in fans.values():
		var component: int=root(parents,parents.keys()[0])
		for face in parents:
			if root(parents,face)!=component:return CONTACT_MESSAGE
	return ""

static func add_edge(edges: Dictionary,a: int,b: int,face: int):
	var key:=Vector2i(mini(a,b),maxi(a,b))
	if not edges.has(key):edges[key]=[]
	edges[key].append(Vector2i(face,1 if a<b else -1))

static func root(parents: Dictionary,face: int) -> int:
	var result:=face
	while parents[result]!=result:result=parents[result]
	while parents[face]!=face:
		var next: int=parents[face];parents[face]=result;face=next
	return result

static func clean_faces(faces: Array) -> Array:
	# CSG occasionally emits collapsed, zero-area triangles at coplanar seams.
	# Discard only exact degeneracies, never slivers or other nonzero geometry.
	var result: Array=[]
	for i in range(0,faces.size(),3):
		var a:=Vector3(faces[i][0],faces[i][1],faces[i][2])
		var b:=Vector3(faces[i+1][0],faces[i+1][1],faces[i+1][2])
		var c:=Vector3(faces[i+2][0],faces[i+2][1],faces[i+2][2])
		if (b-a).cross(c-a)==Vector3.ZERO:continue
		result.append_array([faces[i],faces[i+1],faces[i+2]])
	return result
