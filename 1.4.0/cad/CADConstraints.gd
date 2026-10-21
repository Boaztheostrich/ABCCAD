extends RefCounted
## Directional dependency solver: new geometry follows existing geometry.
## Polylines share endpoints by construction; rectangles are centered and orthogonal.
static func point(p: Array) -> Vector2: return Vector2(p[0],p[1])

static func infer(sketches: Array, current: Dictionary, raw: Vector2, tolerance: float) -> Dictionary:
	var best := {"point":raw,"constraint":{},"label":""}
	var distance := tolerance
	if current.kind=="circle" and current.points.size()==1:
		return best  # A radius point must not snap back to its own center.
	var candidates: Array=[]
	var own_start_origin: bool=current.kind in ["line","rectangle"] and not current.points.is_empty() and point(current.points[0]).length()<0.001
	if not (own_start_origin and current.points.size()<3):
		candidates.append({"point":Vector2.ZERO,"constraint":{"kind":"origin"},"label":"⊙ Origin"})
	for s in sketches:
		if s.plane != current.plane: continue
		var points: Array = s.points
		for i in points.size():
			if s.id==current.id and (i==points.size()-1 or (i==0 and points.size()<3)): continue
			candidates.append({"point":point(points[i]),"constraint":{"kind":"coincident","target":s.id,"index":i},"label":"● Coincident" if s.kind=="line" else "⊙ Center" if i==0 else "● Coincident"})
		for i in s.get("projected_centers",[]).size():
			candidates.append({"point":point(s.projected_centers[i]),"constraint":{"kind":"projected_center","target":s.id,"index":i},"label":"⊙ Projected circle center"})
		for i in s.get("projected_edges",[]).size():
			var edge: Array=s.projected_edges[i]
			for t in [0.0,1.0,0.5]:
				var p: Vector2=point(edge[0]).lerp(point(edge[1]),t)
				candidates.append({"point":p,"constraint":{"kind":"projected_point","target":s.id,"index":i,"t":t},"label":"△ Projected midpoint" if t==0.5 else "● Projected endpoint"})
		if s.kind=="line":
			var count: int = points.size() if s.closed else points.size()-1
			for i in range(maxi(0,count)):
				if s.id==current.id and not s.closed and i==points.size()-2: continue
				candidates.append({"point":(point(points[i])+point(points[(i+1)%points.size()]))/2,"constraint":{"kind":"midpoint","target":s.id,"index":i},"label":"△ Midpoint"})
	for candidate in candidates:
		if not current.points.is_empty() and candidate.point.distance_to(point(current.points[-1]))<0.001: continue
		if current.kind=="line" and current.points.size() in [1,2] and candidate.point.distance_to(point(current.points[0]))<0.001: continue
		var d: float = raw.distance_to(candidate.point)
		if d<distance: best=candidate; distance=d
	if not best.constraint.is_empty(): return best
	if current.kind!="line" or current.points.is_empty() or current.closed: return best
	var start := point(current.points[-1])
	var delta := raw-start
	if delta.length()<0.001: return best
	var direction := delta.normalized()
	if absf(delta.y)<tolerance and absf(delta.y)<=absf(delta.x):
		return align(sketches,current,raw,tolerance,{"point":Vector2(raw.x,start.y),"constraint":{"kind":"horizontal"},"label":"— Horizontal"})
	if absf(delta.x)<tolerance:
		return align(sketches,current,raw,tolerance,{"point":Vector2(start.x,raw.y),"constraint":{"kind":"vertical"},"label":"│ Vertical"})
	for s in sketches:
		if s.plane!=current.plane: continue
		if s.kind=="circle" and s.points.size()==2:
			var center := point(s.points[0])
			var radius := center.distance_to(point(s.points[1]))
			var v := start-center
			var square := v.length_squared()
			if square>radius*radius:
				for sign in [-1,1]:
					var tangent: Vector2 = center+v*(radius*radius/square)+Vector2(-v.y,v.x)*(sign*radius*sqrt(square-radius*radius)/square)
					if tangent.distance_to(raw)<distance:
						distance=tangent.distance_to(raw)
						best={"point":tangent,"constraint":{"kind":"tangent","target":s.id,"sign":sign},"label":"⌒ Tangent"}
		if s.kind!="line": continue
		for i in range(maxi(0,s.points.size()-1)):
			if s.id==current.id and i==s.points.size()-2: continue
			var edge := point(s.points[i+1])-point(s.points[i])
			if edge.length()<0.001: continue
			for perpendicular in [false,true]:
				var axis := edge.normalized()
				if perpendicular: axis=Vector2(-axis.y,axis.x)
				if absf(direction.dot(axis))>cos(deg_to_rad(30)):
					var projected := start+axis*delta.dot(axis)
					if projected.distance_to(raw)<distance:
						distance=projected.distance_to(raw)
						best={"point":projected,"constraint":{"kind":"perpendicular" if perpendicular else "parallel","target":s.id,"index":i},"label":"⊥ Perpendicular" if perpendicular else "∥ Parallel"}
			if absf(delta.length()-edge.length())<distance:
				distance=absf(delta.length()-edge.length())
				best={"point":start+direction*edge.length(),"constraint":{"kind":"equal","target":s.id,"index":i},"label":"= Equal length"}
	return align(sketches,current,raw,tolerance,best)

static func align(sketches: Array,current: Dictionary,raw: Vector2,tolerance: float,best: Dictionary) -> Dictionary:
	# Each axis may align to an earlier point while the new segment remains
	# horizontal/vertical to its own start (e.g. the fourth rectangle corner).
	var primary: String=best.constraint.get("kind","")
	if primary not in ["","horizontal","vertical"]: return best
	var snapped: Vector2=best.point
	var extra: Array=[]
	var guides: Array=[]
	for axis in 2:
		if (axis==0 and primary=="vertical") or (axis==1 and primary=="horizontal"): continue
		var nearest:=tolerance
		var reference: Dictionary={}
		for s in sketches:
			if s.plane!=current.plane: continue
			for i in s.points.size():
				if s.id==current.id and i==s.points.size()-1: continue
				var p:=point(s.points[i])
				# Near-coincident snaps already take precedence; this is a guide
				# extending away from an existing point, not a duplicate endpoint.
				if raw.distance_to(p)<tolerance: continue
				var delta: float=absf(raw[axis]-p[axis])
				if delta<nearest:
					nearest=delta; reference={"point":p,"target":s.id,"index":i}
		if reference.is_empty(): continue
		snapped[axis]=reference.point[axis]
		extra.append({"kind":"vertical_align" if axis==0 else "horizontal_align","target":reference.target,"index":reference.index})
		guides.append([reference.point,snapped])
	if extra.is_empty(): return best
	var constraint: Dictionary=best.constraint.duplicate(true)
	if constraint.is_empty(): constraint=extra.pop_front()
	if not extra.is_empty(): constraint.also=extra
	for pair in guides: pair[1]=snapped
	return {"point":snapped,"constraint":constraint,"label":best.label+(" · " if not best.label.is_empty() else "")+("Vertical alignment" if guides[0][0].x==snapped.x else "Horizontal alignment"),"guides":guides}

static func solve(sketches: Array):
	var registry := {}
	for s in sketches: registry[int(s.id)]=s
	var order:=dependency_order(sketches)
	for s in order:

		for c in s.get("constraints",[]):
			var index: int = c.get("point",-1)
			if index<0 or index>=s.points.size(): continue
			var p := point(s.points[index])
			var previous := point(s.points[maxi(0,index-1)])
			var target: Dictionary = registry.get(int(c.get("target",-1)),{})
			var target_index: int = c.get("index",0)
			if c.kind=="origin": p=Vector2.ZERO
			elif c.kind=="horizontal": p.y=previous.y
			elif c.kind=="vertical": p.x=previous.x
			elif c.kind=="projected_center" and not target.is_empty(): p=point(target.projected_centers[target_index])
			elif c.kind=="projected_point" and not target.is_empty():
				var edge: Array=target.projected_edges[target_index]
				p=point(edge[0]).lerp(point(edge[1]),float(c.t))
			elif not target.is_empty() and target.points.size()>target_index and target_index>=0:
				var a := point(target.points[target_index])
				var b := point(target.points[(target_index+1)%target.points.size()])
				match c.kind:
					"vertical_align": p.x=a.x
					"horizontal_align": p.y=a.y
					"coincident": p=a
					"midpoint": p=(a+b)/2
					"equal": p=previous+(p-previous).normalized()*a.distance_to(b)
					"parallel","perpendicular":
						var axis := (b-a).normalized()
						if c.kind=="perpendicular": axis=Vector2(-axis.y,axis.x)
						if (p-previous).dot(axis)<0: axis=-axis
						p=previous+axis*p.distance_to(previous)
					"tangent":
						if target.kind!="circle" or target.points.size()!=2: continue
						var v := previous-a
						var square := v.length_squared()
						var r := a.distance_to(b)
						if square>r*r: p=a+v*(r*r/square)+Vector2(-v.y,v.x)*(int(c.get("sign",1))*r*sqrt(square-r*r)/square)
				s.points[index]=[p.x,p.y]
				continue
			s.points[index]=[p.x,p.y]

		# Solve before downstream sketches evaluate their dependencies.
		if s.get("constraints",[]).any(func(c): return c.kind=="dimension"):
			preload("res://cad/CADSketchConstraints.gd").solve(s,registry)

static func dependency_order(sketches: Array) -> Array:
	var registry: Dictionary={}
	var dependencies: Dictionary={}
	var result: Array=[]
	for s in sketches:
		registry[int(s.id)]=s
		dependencies[int(s.id)]={}
		for c in s.get("constraints",[]):
			if c.kind not in ["projected_point","projected_center"] and c.has("target") and int(c.target)!=int(s.id): dependencies[int(s.id)][int(c.target)]=true
	while result.size()<sketches.size():
		var ready: Array=[]
		for id in dependencies:
			if dependencies[id].is_empty(): ready.append(id)
		if ready.is_empty(): return []
		for id in ready:
			result.append(registry[id])
			dependencies.erase(id)
		for id in dependencies:
			for done in ready: dependencies[id].erase(done)
	return result
