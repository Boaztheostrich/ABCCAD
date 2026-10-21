extends RefCounted
## Numeric residual solver for driving dimensions; rank describes remaining
## freedoms, rather than treating the presence of any constraint as fully fixed.
static func v(s: Dictionary,i: int) -> Vector2:
	return Vector2(s.points[i][0],s.points[i][1])

static func residuals(s: Dictionary,registry: Dictionary,allowed: Array=[]) -> PackedFloat64Array:
	var out:=PackedFloat64Array()
	for c in s.get("constraints",[]):
		if not allowed.is_empty() and not c in allowed: continue
		var i:=int(c.point)
		if i<0 or i>=s.points.size(): continue
		var p:=v(s,i)
		var previous:=v(s,(i+s.points.size()-1)%s.points.size())
		var target: Dictionary=registry.get(int(c.get("target",-1)),{})
		if c.kind=="origin": out.append(p.x); out.append(p.y)
		elif c.kind=="horizontal": out.append(p.y-previous.y)
		elif c.kind=="vertical": out.append(p.x-previous.x)
		elif c.kind=="dimension":
			var a:=v(s,0)
			match c.field:
				"angle":
					var g:=preload("res://cad/CADAngleDimension.gd").geometry(s,c)
					out.append(wrapf(g.sweep-float(c.sign)*deg_to_rad(float(c.value)),-PI,PI)*10.0)
				"length": out.append(p.distance_to(previous)-float(c.value))
				"radius": out.append(p.distance_to(a)-float(c.value))
				"width": out.append(absf(p.x-a.x)*2-float(c.value))
				"height": out.append(absf(p.y-a.y)*2-float(c.value))
		elif c.kind=="projected_center" and not target.is_empty():
			var center: Array=target.projected_centers[int(c.index)]
			out.append(p.x-float(center[0]));out.append(p.y-float(center[1]))
		elif c.kind=="projected_point" and not target.is_empty():
			var edge: Array=target.projected_edges[int(c.index)]
			var a:=Vector2(edge[0][0],edge[0][1]).lerp(Vector2(edge[1][0],edge[1][1]),float(c.t))
			out.append(p.x-a.x); out.append(p.y-a.y)
		elif not target.is_empty():
			var j:=int(c.get("index",0))
			var a:=v(target,j)
			var b:=v(target,(j+1)%target.points.size())
			match c.kind:
				"vertical_align": out.append(p.x-a.x)
				"horizontal_align": out.append(p.y-a.y)
				"coincident": out.append(p.x-a.x); out.append(p.y-a.y)
				"midpoint": out.append(p.x-(a.x+b.x)/2); out.append(p.y-(a.y+b.y)/2)
				"equal": out.append(p.distance_to(previous)-a.distance_to(b))
				"parallel": out.append((p-previous).cross((b-a).normalized()))
				"perpendicular": out.append((p-previous).dot((b-a).normalized()))
				"tangent":
					var radius: float=a.distance_to(b)
					out.append(p.distance_to(a)-radius)
					out.append((p-previous).dot((p-a).normalized()))
	return out

static func jacobian(s: Dictionary,registry: Dictionary,allowed: Array=[]) -> Array:
	var base:=residuals(s,registry,allowed)
	var rows: Array=[]
	for _i in base.size():
		var row:=PackedFloat64Array()
		row.resize(s.points.size()*2)
		rows.append(row)
	for k in s.points.size()*2:
		var i: int=k/2
		var axis: int=k%2
		var old: float=s.points[i][axis]
		s.points[i][axis]=old+0.001
		var changed:=residuals(s,registry,allowed)
		s.points[i][axis]=old
		for r in base.size(): rows[r][k]=(changed[r]-base[r])/0.001
	return rows

static func solve(s: Dictionary,registry: Dictionary) -> bool:
	if s.points.size()>128: return false
	var n: int=s.points.size()*2
	for _iteration in 60:
		var residual:=residuals(s,registry)
		var error:=0.0
		for value in residual: error=maxf(error,absf(value))
		if error<0.00001: return true
		var jac:=jacobian(s,registry)
		var matrix: Array=[]
		for a in n:
			var row:=PackedFloat64Array()
			row.resize(n+1)
			row[a]=0.000001
			for r in jac.size():
				for b in n: row[b]+=jac[r][a]*jac[r][b]
				row[n]-=jac[r][a]*residual[r]
			matrix.append(row)
		for column in n:
			var pivot:=column
			for r in range(column+1,n):
				if absf(matrix[r][column])>absf(matrix[pivot][column]): pivot=r
			var swapped=matrix[column]; matrix[column]=matrix[pivot]; matrix[pivot]=swapped
			var divisor: float=matrix[column][column]
			if absf(divisor)<0.0000000001: continue
			for b in range(column,n+1): matrix[column][b]/=divisor
			for r in n:
				if r==column: continue
				var factor: float=matrix[r][column]
				for b in range(column,n+1): matrix[r][b]-=factor*matrix[column][b]
		for k in n: s.points[k/2][k%2]+=clampf(matrix[k][n],-10000,10000)
	return false

static func state(s: Dictionary,registry: Dictionary,known: Dictionary) -> Dictionary:
	var count: int=s.points.size()
	var fixed: Array=[]
	fixed.resize(count); fixed.fill(false)
	var result: Dictionary={"points":fixed,"fully_defined":false,"segments":[],"freedoms":count*2}
	if count==0 or count>128: return result
	var usable: Array=[]
	for c in s.get("constraints",[]):
		if c.kind in ["projected_point","projected_center"]: usable.append(c); continue
		if not c.has("target") or int(c.target)==int(s.id): usable.append(c); continue
		var other: Dictionary=known.get(int(c.target),{})
		var target: Dictionary=registry.get(int(c.target),{})
		if other.is_empty() or target.is_empty(): continue
		var i:=int(c.get("index",0))
		var j: int=(i+1)%target.points.size()
		if c.kind in ["coincident","vertical_align","horizontal_align"] and other.points[i]: usable.append(c)
		elif c.kind=="midpoint" and other.points[i] and other.points[j]: usable.append(c)
		elif c.kind=="tangent" and other.fully_defined: usable.append(c)
		elif c.kind in ["parallel","perpendicular","equal"] and other.points[i] and other.points[j]: usable.append(c)
	# Empty allowed means all to residuals(), so explicitly use a filtered copy.
	var copy:=s.duplicate(true)
	copy.constraints=usable
	var local_registry:=registry.duplicate()
	local_registry[int(s.id)]=copy
	var rows:=jacobian(copy,local_registry)
	var n:=count*2
	var pivots: Array=[]
	var row_index:=0
	for column in n:
		var best: int=row_index
		for r in range(row_index,rows.size()):
			if absf(rows[r][column])>absf(rows[best][column]): best=r
		if best>=rows.size() or absf(rows[best][column])<0.00001: continue
		var swapped=rows[row_index]; rows[row_index]=rows[best]; rows[best]=swapped
		var divisor: float=rows[row_index][column]
		for k in n: rows[row_index][k]/=divisor
		for r in rows.size():
			if r==row_index: continue
			var factor: float=rows[r][column]
			for k in n: rows[r][k]-=factor*rows[row_index][k]
		pivots.append(column)
		row_index+=1
		if row_index==rows.size(): break
	var nullspace: Array=[]
	for column in n:
		if column in pivots: continue
		var direction:=PackedFloat64Array()
		direction.resize(n); direction[column]=1.0
		for r in pivots.size(): direction[pivots[r]]=-rows[r][column]
		nullspace.append(direction)
	for i in count:
		fixed[i]=true
		for direction in nullspace:
			if absf(direction[i*2])+absf(direction[i*2+1])>0.0001: fixed[i]=false
	result.freedoms=nullspace.size()
	if s.kind=="circle" and count==2:
		var radial: Vector2=(v(s,1)-v(s,0)).normalized()
		var stable_radius:=true
		for direction in nullspace:
			if absf(radial.dot(Vector2(direction[2]-direction[0],direction[3]-direction[1])))>0.0001: stable_radius=false
		result.fully_defined=fixed[0] and stable_radius
	else: result.fully_defined=not fixed.has(false)
	if s.kind=="line":
		var edges: int=count if s.closed else count-1
		for i in maxi(0,edges): result.segments.append(fixed[i] and fixed[(i+1)%count])
	return result
