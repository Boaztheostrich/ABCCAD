extends RefCounted
## Independent copied reference edges belong to a sketch, not to its line chain.
static func key(p: Vector2) -> String:
	return "%.3f,%.3f" % [p.x,p.y]
static func point(p: Array) -> Vector2:
	return Vector2(p[0],p[1])
static func valid(s: Dictionary) -> bool:
	if s.has("closed_by_projection") and not s.closed_by_projection is bool: return false
	var edges=s.get("projected_edges",[])
	if not edges is Array or edges.size()>10000: return false
	for edge in edges:
		if not edge is Array or edge.size()!=2: return false
		for p in edge:
			if not p is Array or p.size()!=2: return false
			for n in p:
				if not (n is int or n is float) or not is_finite(float(n)) or absf(float(n))>10000000: return false
		if point(edge[0]).distance_to(point(edge[1]))<0.001: return false
	var centers=s.get("projected_centers",[])
	if not centers is Array or centers.size()>1000: return false
	for p in centers:
		if not p is Array or p.size()!=2: return false
		for n in p:
			if not (n is int or n is float) or not is_finite(float(n)) or absf(float(n))>10000000: return false
	return true
static func loop(s: Dictionary) -> PackedVector2Array:
	var edges: Array=s.get("projected_edges",[])
	if edges.is_empty(): return PackedVector2Array()
	var positions: Dictionary={}
	for edge in edges:
		for p in edge: positions[key(point(p))]=point(p)
	var drawn: Array=s.points
	if drawn.size()>=2:
		positions[key(point(drawn[0]))]=point(drawn[0])
		positions[key(point(drawn[-1]))]=point(drawn[-1])
	var graph: Dictionary={}
	for edge in edges:
		var a:=point(edge[0]);var b:=point(edge[1]);var axis:=b-a
		var split: Array=[]
		for name_ in positions:
			var p: Vector2=positions[name_]
			var t: float=(p-a).dot(axis)/axis.length_squared()
			if t>=-0.00001 and t<=1.00001 and p.distance_to(a+axis*t)<0.002: split.append({"key":name_,"t":t})
		split.sort_custom(func(x,y): return x.t<y.t)
		for i in range(split.size()-1):
			var x: String=split[i].key;var y: String=split[i+1].key
			if not graph.has(x): graph[x]=[]
			if not graph.has(y): graph[y]=[]
			if not y in graph[x]: graph[x].append(y)
			if not x in graph[y]: graph[y].append(x)
	if drawn.size()>=2:
		var start:=key(point(drawn[-1]));var finish:=key(point(drawn[0]))
		if start==finish or not graph.has(start) or not graph.has(finish): return PackedVector2Array()
		var queue: Array=[start];var previous: Dictionary={start:""}
		while not queue.is_empty() and not previous.has(finish):
			var node: String=queue.pop_front()
			for neighbor in graph[node]:
				if not previous.has(neighbor): previous[neighbor]=node;queue.append(neighbor)
		if not previous.has(finish): return PackedVector2Array()
		var path: Array=[];var at:=finish
		while at!=start: path.push_front(positions[at]);at=previous[at]
		var result:=PackedVector2Array()
		for p in drawn: result.append(point(p))
		# The path ends at the first drawn point; the polygon closes implicitly.
		for i in maxi(0,path.size()-1): result.append(path[i])
		return result if result.size()>=3 else PackedVector2Array()
	if not drawn.is_empty(): return PackedVector2Array()
	# With only projected edges, a simple closed component is an extrudable region.
	for start in graph:
		if graph[start].size()!=2: continue
		var result:=PackedVector2Array([positions[start]])
		var previous: String=start;var current: String=graph[start][0]
		var visited: Dictionary={start:true}
		while current!=start and not visited.has(current) and result.size()<10000:
			if graph[current].size()!=2: break
			visited[current]=true;result.append(positions[current])
			var next: String=graph[current][0] if graph[current][0]!=previous else graph[current][1]
			previous=current;current=next
		if current==start and result.size()>=3: return result
	return PackedVector2Array()
