@tool
extends XRToolsFunctionPointer
## Controller hands already carry XR world scale. Collision distance is
## measured in world units, while the beam mesh expects hand-local units.
func _visible_hit(at: Vector3) -> void:
	super._visible_hit(at)
	_fit_beam(at)

func _visible_move(at: Vector3) -> void:
	super._visible_move(at)
	_fit_beam(at)

func _fit_beam(at: Vector3) -> void:
	if laser_length==LaserLength.COLLIDE:
		var length_: float=maxf(0.0,-to_local(at).z)
		$Laser.mesh.size.z=length_
		$Laser.position.z=-length_/2.0

var _cad_visual_hit:=false
var _ignored_studio_bodies: Array[CollisionObject3D]=[]

func _sync_studio_capture(wb: Node) -> void:
	var captured: bool=enabled and wb!=null and wb.world_drag_active(self)
	var bodies: Array[CollisionObject3D]=[]
	if captured: bodies=wb.pointer_ui_bodies()
	if bodies==_ignored_studio_bodies: return
	for body in _ignored_studio_bodies:
		if is_instance_valid(body): $RayCast.remove_exception(body)
	_ignored_studio_bodies=bodies
	for body in bodies: $RayCast.add_exception(body)
	$RayCast.force_raycast_update()

func _process(delta):
	var wb=get_tree().get_first_node_in_group("cad_workbench") if not Engine.is_editor_hint() else null
	# Only this hand passes through the studio while it owns a world drag.
	_sync_studio_capture(wb)
	super._process(delta)
	if Engine.is_editor_hint() or not enabled: return
	# Menu collision stays authoritative because menus render above the scene.
	if wb and wb.is_modeling() and not $RayCast.is_colliding():
		var hit: Dictionary=wb.pointer_surface_hit(self)
		if not hit.is_empty():
			_visible_hit(hit.point)
			_cad_visual_hit=true
			return
	if _cad_visual_hit:
		if last_target: _visible_hit(last_collided_at)
		else: _visible_miss()
		_cad_visual_hit=false
