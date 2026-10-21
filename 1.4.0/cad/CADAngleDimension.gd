extends RefCounted
## An angle refers to two connected segments in the same line sketch.
static func point(s: Dictionary,i: int) -> Vector2:
	return Vector2(s.points[i][0],s.points[i][1])

static func pair(s: Dictionary,first: int,second: int) -> Dictionary:
	var n: int=s.points.size()
	var count: int=n if s.closed and not s.get("closed_by_projection",false) else n-1
	if s.kind!="line" or first==second or mini(first,second)<0 or maxi(first,second)>=count: return {}
	for a in [first,(first+1)%n]:
		for b in [second,(second+1)%n]:
			if a!=b: continue
			var outer_a: int=(first+1)%n if a==first else first
			var outer_b: int=(second+1)%n if b==second else second
			if point(s,a).distance_to(point(s,outer_a))<0.01 or point(s,a).distance_to(point(s,outer_b))<0.01: return {}
			var c: Dictionary={"kind":"dimension","field":"angle","vertex":a,"point":outer_a,"other":outer_b,"flip_a":1,"flip_b":1,"radius":20.0}
			var g:=geometry(s,c)
			if absf(g.sweep)<0.001 or absf(g.sweep)>PI-0.001: return {}
			c.sign=1 if g.sweep>0 else -1
			c.value=rad_to_deg(absf(g.sweep))
			return c
	return {}

static func geometry(s: Dictionary,c: Dictionary) -> Dictionary:
	var center:=point(s,int(c.vertex))
	var a: Vector2=(point(s,int(c.point))-center).normalized()*int(c.flip_a)
	var b: Vector2=(point(s,int(c.other))-center).normalized()*int(c.flip_b)
	var sweep:=atan2(a.cross(b),a.dot(b))
	var mid:=a.rotated(sweep/2)
	return {"center":center,"a":a,"b":b,"sweep":sweep,"label":center+mid*float(c.radius)}

static func placed(s: Dictionary,base: Dictionary,at: Vector2) -> Dictionary:
	var best: Dictionary=base.duplicate(true)
	var score:=-INF
	for fa in [1,-1]:
		for fb in [1,-1]:
			var c:=base.duplicate(true); c.flip_a=fa; c.flip_b=fb
			var g:=geometry(s,c)
			var direction: Vector2=(at-g.center).normalized()
			var middle: Vector2=g.a.rotated(g.sweep/2)
			var candidate:=middle.dot(direction)
			if candidate>score:
				score=candidate;best=c
	var g:=geometry(s,best)
	best.radius=clampf(at.distance_to(g.center),8,10000)
	best.sign=1 if g.sweep>0 else -1
	best.value=rad_to_deg(absf(g.sweep))
	return best

static func valid(s: Dictionary,c: Dictionary) -> bool:
	if s.kind!="line": return false
	for key in ["point","vertex","other","flip_a","flip_b","sign","radius","value"]:
		if not (c.get(key) is int or c.get(key) is float) or not is_finite(float(c[key])): return false
	for key in ["point","vertex","other"]:
		if float(c[key])!=int(c[key]) or int(c[key])<0 or int(c[key])>=s.points.size(): return false
	if c.vertex==c.point or c.vertex==c.other or c.point==c.other: return false
	if float(c.flip_a) not in [-1.0,1.0] or float(c.flip_b) not in [-1.0,1.0] or float(c.sign) not in [-1.0,1.0]: return false
	var n: int=s.points.size()
	for outer in [int(c.point),int(c.other)]:
		if absi(outer-int(c.vertex))!=1 and not (s.closed and not s.get("closed_by_projection",false) and absi(outer-int(c.vertex))==n-1): return false
	return float(c.radius)>=8 and float(c.radius)<=10000 and float(c.value)>0.01 and float(c.value)<179.99
