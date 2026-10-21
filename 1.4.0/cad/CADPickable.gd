extends "res://addons/godot-xr-tools/objects/pickable.gd"
## CAD pickup uses a convex interaction hull. The saved/exported mesh stays exact.
var document: Node3D
var body_id := -1
var _baseline: Dictionary = {}
var _sketches: Dictionary = {}
var _last := Transform3D.IDENTITY
var _moving := false
var model_transform := Transform3D.IDENTITY
var _start_model := Transform3D.IDENTITY

func _ready():
	super._ready()
	grabbed.connect(_begin_move)
	dropped.connect(_finish_move,CONNECT_DEFERRED)
	for controller in get_tree().get_nodes_in_group("block_controllers"):
		grabbed.connect(Callable(controller,"on_cube_grabbed"))
		released.connect(Callable(controller,"on_cube_released"))

func can_pick_up(by: Node3D) -> bool:
	if document.busy and document.active_grabs.is_empty(): return false
	return super.can_pick_up(by)

func pick_up(by: Node3D) -> void:
	# CAD supports one rigid grab, with a continuous transaction on hand swap.
	if is_picked_up():
		if second_hand_grab!=SecondHandGrab.SWAP: return
		let_go(_grab_driver.primary.by,Vector3.ZERO,Vector3.ZERO)
	var pose:=global_transform
	pose.basis=pose.basis.orthonormalized()
	var hand_pose:=by.global_transform
	hand_pose.basis=hand_pose.basis.orthonormalized()
	var grab:=Grab.new(Grabber.new(by),self,null,false)
	grab.transform=pose.affine_inverse()*hand_pose if not by.picked_up_ranged else Transform3D.IDENTITY
	restore_freeze=true
	freeze=true
	collision_layer=picked_up_layer
	collision_mask=0
	var driver=preload("res://cad/CADGrabDriver.gd").new()
	driver.name=name+"_driver"
	driver.top_level=true
	driver.process_physics_priority=-80
	driver.target=self
	driver.primary=grab
	driver.transform=pose
	driver.update_scale=false
	_grab_driver=driver
	get_parent().add_child(driver)
	driver.remote_path=driver.get_path_to(self)
	grab.set_arrived()
	driver._update_weight()
	picked_up.emit(self)
	grabbed.emit(self,by)

func _begin_move(_object, _by):
	if _moving: return # A hand swap is still one placement transaction.
	if document.active_grabs.is_empty(): document.checkpoint()
	_baseline=document.body(body_id).duplicate(true)
	_sketches={}
	for s in document.sketches:
		if int(s.body_id)==body_id: _sketches[int(s.id)]=s.duplicate(true)
	_start_model=model_transform
	_last=global_transform
	_moving=true
	document.active_grabs[body_id]=true
	document.busy=true
	var wb=get_tree().get_first_node_in_group("cad_workbench")
	if wb:
		wb.selected_body=body_id
		wb.selected_hit={}
		if int(document.sketch(wb.active_sketch).get("body_id",-1))!=body_id:
			for sid in _sketches:
				wb.active_sketch=int(sid)
				break
	document.changed.emit()

func _physics_process(_delta):
	if _moving and not global_transform.is_equal_approx(_last):
		_sync_pose()

func _sync_pose():
	var ref: Dictionary=document.reference_plane
	var view: Transform3D=document.view_transform
	if ref.get("locked",false) and ref.get("lock_rotation",false):
		global_basis=view.basis.orthonormalized()*_start_model.basis
	var inverse:=view.affine_inverse()
	model_transform=Transform3D((inverse.basis*global_basis).orthonormalized(),inverse*global_position)
	var delta:=model_transform*_start_model.affine_inverse()
	if delta.origin.length()<0.0000001 and delta.basis.is_equal_approx(Basis.IDENTITY):
		delta=Transform3D.IDENTITY
		model_transform=_start_model
	var millimeters:=Transform3D(delta.basis,delta.origin*1000.0)
	document.apply_body_pose(body_id,_baseline,_sketches,millimeters)
	_last=global_transform
	var wb=get_tree().get_first_node_in_group("cad_workbench")
	if wb: wb._redraw()

func _finish_move(_object):
	if is_queued_for_deletion() or is_picked_up() or not _moving: return
	_sync_pose()
	_moving=false
	freeze=true
	linear_velocity=Vector3.ZERO
	angular_velocity=Vector3.ZERO
	document.active_grabs.erase(body_id)
	document.busy=not document.active_grabs.is_empty()
	document.status.emit("Part placed. Sketches and dimensions preserved.")
	document.changed.emit()

func dispose():
	# Release pickup state before rebuilding/loading/deleting a rendered body.
	if is_picked_up(): drop()
	_moving=false
	document.active_grabs.erase(body_id)
	queue_free()

func update_view():
	var display: Transform3D=document.view_transform*model_transform
	global_transform=Transform3D(display.basis.orthonormalized(),display.origin)
	var scale_: float=document.view_transform.basis.x.length()
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D: child.scale=Vector3.ONE*scale_
