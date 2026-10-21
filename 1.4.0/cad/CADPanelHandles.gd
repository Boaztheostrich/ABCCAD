extends Node3D
## Laser + trigger moves/resizes only the studio window, never CAD geometry.
var workbench: Node3D
var panel: Node3D
var active_hand: Node3D
var action:=""
var size_factor:=1.0
var distance:=0.0
var grab_local:=Vector3.ZERO
var anchor:=Vector3.ZERO
var drag_plane:=Transform3D.IDENTITY
var start_diagonal:=1.0
var start_size:=1.0

func _ready():
	_add_handle("Move",Vector3(0,-0.42,0),Vector3(0.20,0.026,0.016),true)
	_add_handle("Resize",Vector3(0.48,-0.40,0),Vector3(0.045,0.045,0.016),false)

func _add_handle(label: String,at: Vector3,dimensions: Vector3,pill: bool):
	var body:=StaticBody3D.new()
	body.name=label
	body.collision_layer=5242880
	body.collision_mask=0
	body.position=at
	add_child(body)
	var visual:=MeshInstance3D.new()
	if pill:
		var mesh:=CapsuleMesh.new()
		mesh.radius=dimensions.y/2
		mesh.height=dimensions.x
		visual.mesh=mesh
		visual.rotation.z=PI/2
	else:
		var mesh:=BoxMesh.new()
		mesh.size=dimensions
		visual.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("83baff")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override=material
	body.add_child(visual)
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=dimensions+Vector3(0.018,0.018,0.012)
	shape.shape=box
	body.add_child(shape)
	panel.visibility_changed.connect(func(): shape.set_deferred("disabled",not panel.visible))
	shape.disabled=not panel.visible

func hit(hand: Node3D) -> String:
	var point:=_intersection(hand,panel.global_transform)
	if point.is_empty(): return ""
	var p: Vector3=point.local
	if absf(p.x)<0.12 and absf(p.y+0.42)<0.03: return "move"
	if absf(p.x-0.48)<0.04 and absf(p.y+0.40)<0.04: return "resize"
	return ""

func handle_input(hand: Node3D,pressed: bool,just_pressed: bool) -> bool:
	if active_hand:
		if active_hand!=hand: return true
		if not pressed:
			active_hand=null
			action=""
			return true
		if action=="move":
			var contact: Vector3=hand.global_position-hand.global_basis.z.normalized()*distance
			# Keep the actual pill point under the laser while the panel turns.
			for _i in 4:
				panel.global_position=contact-panel.global_basis*grab_local
				_face_viewer()
			panel.global_position=contact-panel.global_basis*grab_local
		else:
			var point:=_intersection(hand,drag_plane)
			if not point.is_empty():
				var new_size:=clampf(start_size*point.world.distance_to(anchor)/start_diagonal,0.45,2.5)
				size_factor=new_size
				var scale_: float=XRServer.world_scale*size_factor
				panel.global_basis=drag_plane.basis.orthonormalized().scaled(Vector3.ONE*scale_)
				panel.global_position=anchor-panel.global_basis*Vector3(-0.45,0.375,0)
		workbench._remember_panel_pose()
		return true
	var target:=hit(hand)
	if target.is_empty(): return false
	if just_pressed:
		active_hand=hand
		action=target
		var point:=_intersection(hand,panel.global_transform)
		distance=hand.global_position.distance_to(point.world)
		grab_local=panel.to_local(point.world)
		drag_plane=panel.global_transform
		anchor=panel.global_transform*Vector3(-0.45,0.375,0)
		start_diagonal=point.world.distance_to(anchor)
		start_size=size_factor
	return true

func _intersection(hand: Node3D,plane: Transform3D) -> Dictionary:
	var inverse:=plane.affine_inverse()
	var p: Vector3=inverse*hand.global_position
	var d: Vector3=inverse.basis*(-hand.global_basis.z.normalized())
	if absf(d.z)<0.00001: return {}
	var t: float=-p.z/d.z
	if t<=0: return {}
	var local:=p+d*t
	return {"local":local,"world":plane*local}

func cancel():
	active_hand=null
	action=""

func _face_viewer():
	var away: Vector3=panel.global_position-workbench.camera.global_position
	if away.length()<0.01*XRServer.world_scale: return
	var up:=Vector3.UP
	if absf(away.normalized().dot(up))>0.98: up=workbench.camera.global_basis.y
	var scale_: float=XRServer.world_scale*size_factor
	panel.global_basis=Basis.looking_at(away.normalized(),up).scaled(Vector3.ONE*scale_)
