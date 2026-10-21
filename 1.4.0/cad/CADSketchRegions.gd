extends RefCounted
## A planar segment arrangement. Bounded half-edge walks are selectable cells;
## disconnected nested loops become holes, rather than overlapping filled faces.
const Doc=preload("res://cad/CADDocument.gd")
const EPS=0.001
static func key(p: Vector2) -> String:
	var x:=snappedf(p.x,EPS);var y:=snappedf(p.y,EPS)
	return "%.3f,%.3f" % [0.0 if absf(x)<EPS else x,0.0 if absf(y)<EPS else y]
static func point(p) -> Vector2:
	return Vector2(p[0],p[1])
static func area(poly: PackedVector2Array) -> float:
	var sum:=0.0
	for i in poly.size(): sum+=poly[i].cross(poly[(i+1)%poly.size()])
	return sum/2.0
static func sample(poly: PackedVector2Array) -> Vector2:
	var indices:=Geometry2D.triangulate_polygon(poly)
	if indices.size()<3:return Vector2.ZERO
	return (poly[indices[0]]+poly[indices[1]]+poly[indices[2]])/3.0
static func contains(region: Dictionary,at: Vector2) -> bool:
	if region.has("bounds") and not region.bounds.grow(EPS).has_point(at):return false
	if not Geometry2D.is_point_in_polygon(at,region.outer): return false
	for hole in region.holes:
		if Geometry2D.is_point_in_polygon(at,hole): return false
	return true
static func segments(entities: Array) -> Array:
	var result: Array=[]
	for s in entities:
		var poly:=PackedVector2Array()
		if s.kind=="line":
			for p in s.points:poly.append(point(p))
		else:poly=Doc.profile(s)
		var count: int=poly.size() if s.closed and not s.get("closed_by_projection",false) else poly.size()-1
		if s.kind!="line":count=poly.size() if s.closed else 0
		for i in maxi(0,count):
			var a:=poly[i];var b:=poly[(i+1)%poly.size()]
			if a.distance_to(b)>EPS:result.append({"a":a,"b":b,"source":"%d:%d" % [s.id,i]})
		for i in s.get("projected_edges",[]).size():
			var edge: Array=s.projected_edges[i]
			result.append({"a":point(edge[0]),"b":point(edge[1]),"source":"%d:p%d" % [s.id,i]})
	return result
static func build(entities: Array) -> Array:
	var edges:=segments(entities)
	var circles: Dictionary={};var axes: Dictionary={}
	for entity in entities:
		if entity.kind=="circle" and entity.closed:circles[str(entity.id)]=true
	for edge in edges:axes[edge.source]=edge.b-edge.a
	if edges.is_empty(): return []
	var cuts: Array=[]
	for edge in edges:cuts.append([{"t":0.0,"p":edge.a},{"t":1.0,"p":edge.b}])
	# Sweep by X bounding interval before doing segment intersection work.
	var order: Array=[]
	for i in edges.size():order.append(i)
	order.sort_custom(func(a,b):return minf(edges[a].a.x,edges[a].b.x)<minf(edges[b].a.x,edges[b].b.x))
	for oi in order.size():
		var i: int=order[oi];var a: Vector2=edges[i].a;var b: Vector2=edges[i].b
		for oj in range(oi+1,order.size()):
			var j: int=order[oj];var c: Vector2=edges[j].a;var d: Vector2=edges[j].b
			if minf(c.x,d.x)>maxf(a.x,b.x)+EPS:break
			if minf(c.y,d.y)>maxf(a.y,b.y)+EPS or maxf(c.y,d.y)<minf(a.y,b.y)-EPS:continue
			var cross: Variant=Geometry2D.segment_intersects_segment(a,b,c,d)
			if cross!=null:
				cuts[i].append({"t":(cross-a).dot(b-a)/(b-a).length_squared(),"p":cross})
				cuts[j].append({"t":(cross-c).dot(d-c)/(d-c).length_squared(),"p":cross})
			else:
				# Collinear overlaps and T junctions also split the shared edge.
				for item in [[i,a,b,c],[i,a,b,d],[j,c,d,a],[j,c,d,b]]:
					var start: Vector2=item[1];var end: Vector2=item[2];var p: Vector2=item[3]
					var t: float=(p-start).dot(end-start)/(end-start).length_squared()
					if t>=0 and t<=1 and p.distance_to(start+(end-start)*t)<EPS:
						cuts[int(item[0])].append({"t":t,"p":p})
	var positions: Dictionary={};var graph: Dictionary={};var sources: Dictionary={}
	for i in edges.size():
		cuts[i].sort_custom(func(a,b):return a.t<b.t)
		var part:=0
		for j in range(cuts[i].size()-1):
			var a: Vector2=cuts[i][j].p;var b: Vector2=cuts[i][j+1].p
			var ka:=key(a);var kb:=key(b)
			if ka==kb:continue
			positions[ka]=a;positions[kb]=b
			if not graph.has(ka):graph[ka]=[]
			if not graph.has(kb):graph[kb]=[]
			if kb not in graph[ka]:graph[ka].append(kb)
			if ka not in graph[kb]:graph[kb].append(ka)
			var edge_key:=ka+"/"+kb if ka<kb else kb+"/"+ka
			if not sources.has(edge_key):sources[edge_key]=[]
			sources[edge_key].append(edges[i].source+":"+str(part));part+=1
	for node in graph:
		graph[node].sort_custom(func(a,b):return (positions[a]-positions[node]).angle()<(positions[b]-positions[node]).angle())
	var visited: Dictionary={};var loops: Array=[]
	for start in graph:
		for next in graph[start]:
			if visited.has(start+">"+next):continue
			var a: String=start;var b: String=next;var walk: Array=[]
			for step in sources.size()*2+2:
				var directed:=a+">"+b
				if visited.has(directed):break
				visited[directed]=true;walk.append(a)
				var neighbors: Array=graph[b]
				var c: String=neighbors[(neighbors.find(a)+neighbors.size()-1)%neighbors.size()]
				a=b;b=c
				if a==start and b==next:break
			# Remove backtracking spurs from unclosed internal line segments.
			var simplified:=true
			while simplified and walk.size()>=3:
				simplified=false
				for i in walk.size():
					if walk[(i+walk.size()-1)%walk.size()]==walk[(i+1)%walk.size()]:
						walk.remove_at(i);walk.remove_at(i%walk.size());simplified=true;break
			for simple in split_walk(walk):
				walk=simple
				var poly:=PackedVector2Array();var provenance: Array=[]
				for i in walk.size():
					poly.append(positions[walk[i]])
					var u: String=walk[i];var v: String=walk[(i+1)%walk.size()]
					var edge_key:=u+"/"+v if u<v else v+"/"+u
					for source in sources.get(edge_key,[]):
						var parts: PackedStringArray=source.split(":")
						if circles.has(parts[0]) and not parts[1].begins_with("p"):provenance.append(parts[0]+":circle")
						else:
							var name_:=parts[0]+":"+parts[1]
							var axis: Vector2=axes[name_]
							provenance.append(name_+(":L" if (positions[v]-positions[u]).dot(axis)>0 else ":R"))
				var size_:=area(poly)
				if size_<=0.001 or Geometry2D.triangulate_polygon(poly).is_empty():continue
				provenance.sort()
				loops.append({"outer":poly,"holes":[],"area":size_,"sample":sample(poly),"parent":-1,"tokens":provenance,"id":""})
	for i in loops.size():
		var parent:=-1;var size_:=INF
		for j in loops.size():
			if i==j or loops[j].area<=loops[i].area+0.001:continue
			if loops[j].area<size_ and Geometry2D.is_point_in_polygon(loops[i].sample,loops[j].outer):parent=j;size_=loops[j].area
		loops[i].parent=parent
	for i in loops.size():
		if loops[i].parent>=0:loops[int(loops[i].parent)].holes.append(loops[i].outer)
	for region in loops:
		var vertices:=triangles(region);var largest:=-1.0;var witness: Vector2=region.sample
		for i in range(0,vertices.size(),3):
			var size_: float=absf((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]))
			if size_>largest:largest=size_;witness=(vertices[i]+vertices[i+1]+vertices[i+2])/3
		region.sample=witness
		var bounds:=Rect2(region.outer[0],Vector2.ZERO)
		for p in region.outer:bounds=bounds.expand(p)
		region.bounds=bounds
		var center:=Vector2.ZERO
		for p in region.outer:center+=p
		center/=maxi(1,region.outer.size())
		region.anchor=center if contains(region,center) else witness
		var tokens: Dictionary={};var boundary_entities: Dictionary={}
		for token in region.tokens:tokens[token]=true;boundary_entities[token.split(":")[0]]=true
		for entity in entities:
			if entity.closed and boundary_entities.has(str(entity.id)):
				tokens["inside:%d:%s" % [entity.id,Geometry2D.is_point_in_polygon(witness,Doc.profile(entity))]]=true
		var names: Array=tokens.keys();names.sort()
		region.id="|".join(names).sha256_text()
	return loops
static func split_walk(walk: Array) -> Array:
	var pending: Array=[walk];var result: Array=[]
	while not pending.is_empty():
		var current: Array=pending.pop_back();var seen: Dictionary={};var split:=false
		for i in current.size():
			if seen.has(current[i]):
				var first: int=seen[current[i]]
				var cycle:=current.slice(first,i)
				var rest:=current.slice(0,first)+current.slice(i)
				if cycle.size()>=3:pending.append(cycle)
				if rest.size()>=3:pending.append(rest)
				split=true;break
			seen[current[i]]=i
		if not split and current.size()>=3:result.append(current)
	return result

static func packed(regions: Array) -> Array:
	var result: Array=[]
	for r in regions:
		var holes: Array=[]
		for hole in r.holes:
			var points: Array=[]
			for v in hole:points.append([v.x,v.y])
			holes.append(points)
		var outer: Array=[]
		for v in r.outer:outer.append([v.x,v.y])
		result.append({"outer":outer,"holes":holes})
	return result
static func unpacked(regions: Array) -> Array:
	var result: Array=[]
	for r in regions:
		var outer:=PackedVector2Array();var holes: Array=[]
		for p in r.outer:outer.append(point(p))
		for h in r.holes:
			var hole:=PackedVector2Array()
			for p in h:hole.append(point(p))
			holes.append(hole)
		result.append({"outer":outer,"holes":holes})
	return result
static func valid(regions) -> bool:
	if not regions is Array or regions.is_empty() or regions.size()>1000:return false
	for r in regions:
		if not r is Dictionary or not r.get("outer") is Array or not r.get("holes") is Array:return false
		for poly in [r.outer]+r.holes:
			if not poly is Array or poly.size()<3 or poly.size()>10000:return false
			for p in poly:
				if not Doc.valid_vector(p,2):return false
		for poly in unpacked([r]):
			if not Doc.simple_polygon(poly.outer):return false
			for hole in poly.holes:
				if not Doc.simple_polygon(hole):return false
	return true

static func triangles(region: Dictionary) -> PackedVector2Array:
	if region.has("fill"):return region.fill
	# Exact vertical trapezoids support concave outlines and any number of holes.
	# No fill triangle bridges a hole or a concave boundary.
	var xs: Array=[];var edges: Array=[]
	for poly in [region.outer]+region.holes:
		for i in poly.size():
			var a: Vector2=poly[i];var b: Vector2=poly[(i+1)%poly.size()]
			xs.append(a.x)
			if absf(a.x-b.x)>0.000001:edges.append([a,b])
	xs.sort()
	var unique: Array=[]
	for x in xs:
		if unique.is_empty() or x-unique[-1]>0.000001:unique.append(x)
	var vertices:=PackedVector2Array()
	for i in unique.size()-1:
		var x0: float=unique[i];var x1: float=unique[i+1];var mid: float=(x0+x1)/2
		var crossings: Array=[]
		for edge in edges:
			var a: Vector2=edge[0];var b: Vector2=edge[1]
			if mid<minf(a.x,b.x) or mid>maxf(a.x,b.x):continue
			crossings.append({"y":a.y+(b.y-a.y)*(mid-a.x)/(b.x-a.x),"edge":edge})
		crossings.sort_custom(func(a,b):return a.y<b.y)
		for j in range(0,crossings.size()-1,2):
			var corners: Array=[]
			for edge in [crossings[j].edge,crossings[j+1].edge]:
				var a: Vector2=edge[0];var b: Vector2=edge[1]
				for x in [x0,x1]:corners.append(Vector2(x,a.y+(b.y-a.y)*(x-a.x)/(b.x-a.x)))
			for tri in [[corners[0],corners[1],corners[3]],[corners[0],corners[3],corners[2]]]:
				if absf((tri[1]-tri[0]).cross(tri[2]-tri[0]))>0.000001:
					for v in tri:vertices.append(v)
	region.fill=vertices
	return vertices

static func solid_regions(regions: Array) -> Dictionary:
	# Remove shared cell boundaries before CSG. Unioning touching prisms can leave
	# internal walls; a planar boundary union preserves holes and islands exactly.
	var boundary: Dictionary={};var positions: Dictionary={}
	for region in regions:
		for index in region.holes.size()+1:
			var poly: PackedVector2Array=region.outer if index==0 else region.holes[index-1]
			var forward: bool=(area(poly)>0)==(index==0)
			for i in poly.size():
				var a: Vector2=poly[i] if forward else poly[(i+1)%poly.size()]
				var b: Vector2=poly[(i+1)%poly.size()] if forward else poly[i]
				var ka:=key(a);var kb:=key(b)
				positions[ka]=a;positions[kb]=b
				var edge:=ka+"/"+kb;var reverse:=kb+"/"+ka
				if boundary.has(reverse):boundary.erase(reverse)
				elif boundary.has(edge):return {"error":"Selected areas overlap. Select each enclosed area once.","regions":[]}
				else:boundary[edge]=[ka,kb]
	var next: Dictionary={};var previous: Dictionary={}
	for edge in boundary.values():
		if next.has(edge[0]) or previous.has(edge[1]):
			return {"error":preload("res://cad/CADSolidValidation.gd").CONTACT_MESSAGE,"regions":[]}
		next[edge[0]]=edge[1];previous[edge[1]]=edge[0]
	var result: Array=[];var holes: Array=[]
	while not next.is_empty():
		var start: String=next.keys()[0];var at:=start;var poly:=PackedVector2Array()
		while next.has(at):
			poly.append(positions[at]);var following: String=next[at];next.erase(at);at=following
			if at==start:break
		if at!=start or poly.size()<3:return {"error":"Selected areas do not form a closed boundary.","regions":[]}
		if area(poly)>0:result.append({"outer":poly,"holes":[]})
		else:holes.append(poly)
	for hole in holes:
		var parent:=-1;var smallest:=INF
		for i in result.size():
			var size_: float=area(result[i].outer)
			if size_>absf(area(hole)) and size_<smallest and Geometry2D.is_point_in_polygon(hole[0],result[i].outer):
				parent=i;smallest=size_
		if parent<0:return {"error":"Selected areas have an invalid hole boundary.","regions":[]}
		result[parent].holes.append(hole)
	return {"error":"","regions":result}
