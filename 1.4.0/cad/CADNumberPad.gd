extends Node3D
## Independent, stage-fixed numeric editor. Trigger-drag its title bar.
var workbench: Node3D
var panel: Node3D
var active_hand: Node3D
var distance:=0.0
var grab_local:=Vector3.ZERO

func _ready():
	panel=preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn").instantiate()
	panel.name="DimensionWindow"
	panel.screen_size=Vector2(0.32,0.44)
	panel.viewport_size=Vector2(560,770)
	panel.scene=preload("res://cad/CADNumberPadUI.tscn")
	panel.collision_layer=5242880
	var material: StandardMaterial3D=workbench.panel.material.duplicate()
	material.render_priority=121
	panel.material=material
	add_child(panel)
	var keypad: Control=workbench.ui.keypad
	keypad.theme=workbench.ui.theme
	keypad.reparent(panel.get_node("Viewport").get_child(0))
	keypad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keypad.visibility_changed.connect(_sync_visibility)
	_sync_visibility()

func _sync_visibility():
	panel.visible=workbench.ui.keypad.visible
	if not panel.visible: active_hand=null

func open(at: Vector3=Vector3.INF):
	if not panel.visible:
		var eye: Transform3D=workbench.camera.global_transform
		var scale_: float=XRServer.world_scale
		var direction: Vector3=-eye.basis.z
		var reach:=0.65*scale_
		if at.is_finite() and at.distance_to(eye.origin)>0.01*scale_:
			direction=(at-eye.origin).normalized()
			reach=clampf(at.distance_to(eye.origin),0.55*scale_,0.85*scale_)
		panel.global_position=eye.origin+direction*reach+eye.basis.x*0.23*scale_
		_face_viewer()
	workbench.ui.keypad.visible=true

func _face_viewer():
	var away: Vector3=panel.global_position-workbench.camera.global_position
	if away.length_squared()<0.000001: return
	var up:=Vector3.UP
	if absf(away.normalized().dot(up))>0.98: up=workbench.camera.global_basis.y
	panel.global_basis=Basis.looking_at(away,up).scaled(Vector3.ONE*XRServer.world_scale)

func intersection(hand: Node3D) -> Dictionary:
	if not panel.visible: return {}
	var inverse: Transform3D=panel.global_transform.affine_inverse()
	var p: Vector3=inverse*hand.global_position
	var direction: Vector3=inverse.basis*(-hand.global_basis.z.normalized())
	if absf(direction.z)<0.00001: return {}
	var t: float=-p.z/direction.z
	if t<=0: return {}
	var at:=p+direction*t
	if absf(at.x)>panel.screen_size.x/2 or absf(at.y)>panel.screen_size.y/2: return {}
	return {"local":at,"world":panel.global_transform*at}

func handle_input(hand: Node3D,pressed: bool,just_pressed: bool) -> bool:
	if not panel.visible: return false
	if active_hand:
		if hand!=active_hand: return true
		if not pressed:
			active_hand=null
			return true
		var contact: Vector3=hand.global_position-hand.global_basis.z.normalized()*distance
		for _i in 4:
			panel.global_position=contact-panel.global_basis*grab_local
			_face_viewer()
		panel.global_position=contact-panel.global_basis*grab_local
		return true
	var hit:=intersection(hand)
	if hit.is_empty(): return false
	# Top 66 viewport pixels form the draggable title bar.
	if just_pressed and hit.local.y>panel.screen_size.y*(0.5-66.0/770.0):
		active_hand=hand
		distance=hand.global_position.distance_to(hit.world)
		grab_local=hit.local
	return true

func cancel_drag(hand: Node3D):
	if active_hand==hand: active_hand=null
