extends Node
## A short trigger click edits; a held trigger moves only annotation placement.
var workbench: Node3D
var hand: Node3D
var dimension: Dictionary={}
var start:=Vector2.ZERO
var original:=Vector2.ZERO
var moved:=false

func plane_point(ray: Node3D,plane: Transform3D) -> Vector2:
	var pose: Transform3D=workbench.document.view_transform*Transform3D(plane.basis,plane.origin*0.001)
	var inverse:=pose.affine_inverse()
	var p: Vector3=inverse*ray.global_position
	var direction: Vector3=inverse.basis*(-ray.global_basis.z.normalized())
	if absf(direction.z)<0.00001: return Vector2.INF
	var t: float=-p.z/direction.z
	if t<=0: return Vector2.INF
	var at:=p+direction*t
	return Vector2(at.x,at.y)*1000

func begin(ray: Node3D) -> bool:
	if hand or workbench.tool!="select" or workbench.ui.mode=="extrude" or workbench.document.busy: return false
	var hit: Dictionary=workbench.sketch_visual.hit_dimension(ray)
	if hit.is_empty(): return false
	var at:=plane_point(ray,hit.plane)
	if not at.is_finite(): return false
	hand=ray;dimension=hit;start=at;original=hit.point;moved=false
	return true

func update():
	if not hand: return
	if not is_instance_valid(dimension.node) or dimension.node.is_queued_for_deletion(): end(true);return
	var at:=plane_point(hand,dimension.plane)
	if not at.is_finite(): return
	var delta:=at-start
	var scale_: float=workbench.document.view_transform.basis.x.length()
	if delta.length()*scale_>4.0*XRServer.world_scale: moved=true
	if not moved: return
	var target:=original+delta
	if absf(target.x)>100000 or absf(target.y)>100000: return
	workbench.sketch_visual.position_dimension(dimension,target)

func end(cancel: bool=false):
	if not hand: return
	var d:=dimension
	var dragged:=moved
	hand=null;dimension={};moved=false
	if cancel:
		workbench.sketch_visual.redraw()
	elif dragged:
		workbench.document.place_dimension_label(int(d.sketch),d.field,d.point-d.preferred)
	else:
		workbench.active_sketch=int(d.sketch)
		workbench.ui.show_command("sketch")
		workbench.ui.edit_number(d.field,d.node.global_position)
