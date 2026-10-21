extends RefCounted
## All contacts are tracking-space meters. The first point is the origin;
## point 1 -> 2 defines X, and the third point fixes the plane's rotation.
static func from_contacts(points: Array) -> Dictionary:
	if points.size()!=3: return {"error":"Touch three different spots."}
	var a: Vector3=points[0]
	var x: Vector3=points[1]-a
	var toward: Vector3=points[2]-a
	if minf(x.length(),minf(toward.length(),points[2].distance_to(points[1])))<0.02:
		return {"error":"Spread the contacts at least 20 mm apart."}
	var normal:=x.cross(toward)
	if normal.length()/(x.length()*toward.length())<0.05:
		return {"error":"The contacts are almost in a line. Touch a wider triangle."}
	x=x.normalized()
	normal=normal.normalized()
	if normal.dot(Vector3.UP)<0: normal=-normal
	var y:=normal.cross(x).normalized()
	return {"pose":Transform3D(Basis(x,y,normal),a)}

static func anchored_view(model_plane_m: Transform3D, world_plane_m: Transform3D, scale_: float) -> Transform3D:
	return world_plane_m*Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_),Vector3.ZERO)*model_plane_m.affine_inverse()
