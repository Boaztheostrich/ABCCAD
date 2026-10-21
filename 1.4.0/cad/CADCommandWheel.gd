extends Node3D
## Right-stick marking menu. A click is edge-triggered and requires neutral to rearm.
var workbench: Node3D
var face: Control
var viewport: SubViewport
var menu: Dictionary={"id":"", "title":"COMMAND", "items":[]}
var selected := -1
var _previous_click := false
var _latched := false
var _candidate := -1
var _candidate_time := 0.0
var _amount := 0.0
var _open := false
const DEADZONE = 0.55
const NEUTRAL = 0.28
const SETTLE = 0.07

func _ready():
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,640)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	face=preload("res://cad/CADCommandWheelFace.gd").new()
	face.size=Vector2(640,640)
	viewport.add_child(face)
	var display:=MeshInstance3D.new()
	var quad:=QuadMesh.new()
	quad.size=Vector2(0.30,0.30)
	display.mesh=quad
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture=viewport.get_texture()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=true
	material.render_priority=125
	display.material_override=material
	display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	visible=false

func reset(click: bool=false):
	selected=-1; _candidate=-1; _candidate_time=0.0
	_open=false; _latched=true; _previous_click=click

func set_menu(value: Dictionary, axis: Vector2=Vector2.ZERO, click: bool=false):
	var identity: Array=value.items.map(func(item):return item.id)
	var previous: Array=menu.items.map(func(item):return item.id)
	if value.id!=menu.id or identity!=previous:
		reset(click)
		_amount=0.0
		# A changed layout cannot be selected with an already tilted stick.
		_latched=axis.length()>=NEUTRAL or click
	menu=value

func update_input(axis: Vector2, click: bool, delta: float, available: bool, count: int=4) -> int:
	var rising:=click and not _previous_click
	_previous_click=click
	if not available or count<1:
		reset(click)
		return -1
	if axis.length()<NEUTRAL:
		selected=-1; _candidate=-1; _candidate_time=0.0; _open=false
		if not click: _latched=false
		return -1
	if _latched: return -1
	if axis.length()>=DEADZONE:
		var width:=TAU/count
		var angle:=fposmod(atan2(axis.x,axis.y),TAU)
		var next:=int(floor((angle+width/2)/width))%count
		# Angular hysteresis works for any wedge count, including diagonals.
		if selected>=0 and selected<count and next!=selected and absf(angle_difference(selected*width,angle))<width/2+0.07: next=selected
		if next!=_candidate: _candidate=next; _candidate_time=0.0
		_candidate_time+=delta
		# The first highlight is immediate; subsequent changes must settle before a click.
		if selected<0 or (_candidate_time>=SETTLE and not click): selected=next
		_open=true
	if rising and _open and selected>=0:
		var action:=selected
		_latched=true; _open=false
		return action
	return -1

func _process(delta: float):
	var hand: XRController3D=workbench.right
	var click:=hand.is_button_pressed("primary_click")
	var available: bool=workbench.is_modeling() and hand.get_is_active() and not workbench.document.busy and not workbench.ui.confirmation.visible and not workbench.ui.keypad.visible and workbench.extrude_arrow.drag_hand==null and not workbench._zooming
	var axis:=hand.get_vector2("primary")
	set_menu(workbench.wheel_context(),axis,click)
	var old:=selected
	var action:=update_input(axis,click,delta,available,menu.items.size())
	if old!=selected and selected>=0 and available:
		hand.trigger_haptic_pulse("haptic",0.0,0.25,0.025,0.0)
	if action>=0:
		workbench.run_wheel_command(str(menu.items[action].id))
	var target:=1.0 if _open and available else 0.0
	_amount=move_toward(_amount,target,delta*9)
	visible=_amount>0.001
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible: return
	global_transform=presentation_transform(hand.global_position,workbench.camera.global_transform,XRServer.world_scale,_amount)
	face.modulate.a=_amount
	face.selected=selected
	face.menu=menu
	face.queue_redraw()

## All offsets use physical meters converted through XR world scale, just like
## the tracked controller and ring size. Never pull the menu toward the headset.
static func presentation_transform(hand_position: Vector3, camera_pose: Transform3D, world_scale: float, reveal: float=1.0) -> Transform3D:
	var view:=camera_pose.orthonormalized()
	var physical_scale:=maxf(world_scale,0.0001)
	var at: Vector3=hand_position+(view.basis.y*0.17-view.basis.z*0.10)*physical_scale
	var away: Vector3=at-view.origin
	var frame:=view.basis
	if away.length_squared()>0.00000001:
		var up:=view.basis.y
		if absf(away.normalized().dot(up))>0.99: up=view.basis.x
		frame=Basis.looking_at(away,up)
	return Transform3D(frame.scaled(Vector3.ONE*physical_scale*lerpf(0.92,1.0,reveal)),at)
