extends Node3D
## A presentation-only direction indicator. Never part of CAD or STL geometry.
var workbench: Node3D
var shaft: MeshInstance3D
var tip: MeshInstance3D
var label: Label3D
var label_hit_size:=Vector2(0.074,0.022)
var start_point:=Vector3.ZERO
var end_point:=Vector3.ZERO
var tip_point:=Vector3.ZERO
var direction:=Vector3.FORWARD
var _signature:=""
var drag_hand: Node3D
var _drag_depth:=0.0
var _drag_axis:=Vector3.ZERO
var _drag_origin:=Vector3.ZERO
var _drag_start:=0.0
var _drag_hand_position:=Vector3.ZERO
var _drag_per_mm:=0.001
var _drag_parallel:=false
func _axis_parameter(hand: Node3D) -> float:
	var ray: Vector3=-hand.global_basis.z.normalized()
	var offset: Vector3=hand.global_position-_drag_origin
	var dot_: float=ray.dot(_drag_axis)
	return (offset.dot(_drag_axis)-offset.dot(ray)*dot_)/maxf(0.0001,1-dot_*dot_)
func begin_drag(hand: Node3D) -> bool:
	if drag_hand!=null or not hit(hand) or workbench.document.busy: return false
	drag_hand=hand; _drag_depth=workbench.depth_mm
	_drag_axis=direction*(1 if workbench.depth_mm>=0 else -1)
	_drag_origin=start_point; _drag_hand_position=hand.global_position
	_drag_parallel=absf((-hand.global_basis.z.normalized()).dot(_drag_axis))>0.95
	_drag_start=_axis_parameter(hand)
	var s: Dictionary=workbench.document.sketch(workbench.active_sketch)
	var plane: Transform3D=preload("res://cad/CADDocument.gd").unpack_transform(s.plane)
	_drag_per_mm=(workbench.document.view_transform.basis*plane.basis.z).length()*0.001
	return true
func update_drag(hand: Node3D):
	if hand!=drag_hand: return
	if not _drag_parallel and absf((-hand.global_basis.z.normalized()).dot(_drag_axis))>0.95:
		# A ray parallel to the axis has no stable closest point. Continue from
		# here using physical push/pull, without jumping to a huge depth.
		_drag_parallel=true; _drag_depth=workbench.depth_mm
		_drag_hand_position=hand.global_position
	var distance: float=(hand.global_position-_drag_hand_position).dot(_drag_axis) if _drag_parallel else _axis_parameter(hand)-_drag_start
	workbench.depth_mm=clampf(snappedf(_drag_depth+distance/_drag_per_mm,0.1),-100000,100000)
	refresh()
func end_drag(cancelled: bool=false):
	if drag_hand==null: return
	if cancelled: workbench.depth_mm=_drag_depth
	drag_hand=null
	workbench._refresh_ui()

func _ready():
	shaft=MeshInstance3D.new(); add_child(shaft)
	tip=MeshInstance3D.new(); add_child(tip)
	var cylinder:=CylinderMesh.new()
	cylinder.top_radius=0.0015; cylinder.bottom_radius=0.0015; cylinder.height=0.03
	shaft.mesh=cylinder
	var cone:=CylinderMesh.new()
	cone.top_radius=0; cone.bottom_radius=0.006; cone.height=0.012
	tip.mesh=cone
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test=true
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority=10
	material.albedo_color=Color("ffad32")
	shaft.material_override=material; tip.material_override=material
	label=Label3D.new(); add_child(label)
	label.font_size=48; label.pixel_size=0.00018
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=true
	label.shaded=false
	label.render_priority=14; label.outline_render_priority=13
	label.modulate=Color.WHITE
	label.outline_size=3; label.outline_modulate=Color.BLACK
	visible=false

func refresh():
	var s: Dictionary=workbench.selected_profile()
	visible=workbench.is_modeling() and workbench.ui.mode=="extrude" and not s.is_empty() and s.get("closed",false) and not workbench.document.busy
	if not visible:
		end_drag(true)
		return
	var signature:=str([workbench._profile_signature,workbench.depth_mm,workbench.operation,workbench.document.view_transform,XRServer.world_scale])
	if signature==_signature:
		_place_label()
		return
	_signature=signature
	var polygon: PackedVector2Array=preload("res://cad/CADDocument.gd").profile(s)
	var center:=Vector2.ZERO
	for p in polygon: center+=p
	center/=maxi(1,polygon.size())
	if s.has("region_anchor"):center=Vector2(s.region_anchor[0],s.region_anchor[1])
	var plane: Transform3D=preload("res://cad/CADDocument.gd").unpack_transform(s.plane)
	var view: Transform3D=workbench.document.view_transform
	start_point=view*(plane*Vector3(center.x,center.y,0)*0.001)
	end_point=view*(plane*Vector3(center.x,center.y,workbench.depth_mm)*0.001)
	direction=(view.basis*plane.basis.z).normalized()*(1 if workbench.depth_mm>=0 else -1)
	var scale_: float=XRServer.world_scale
	var arrow_origin: Vector3=end_point+direction*0.004*scale_
	tip_point=arrow_origin+direction*0.042*scale_
	var x:=direction.cross(Vector3.UP).normalized()
	if x.length()<0.1: x=direction.cross(Vector3.RIGHT).normalized()
	var basis:=Basis(x,direction,x.cross(direction)).orthonormalized().scaled(Vector3.ONE*scale_)
	shaft.global_transform=Transform3D(basis,arrow_origin+direction*0.015*scale_)
	tip.global_transform=Transform3D(basis,arrow_origin+direction*0.036*scale_)
	label.text="%+.2f mm" % workbench.depth_mm
	var width: float=maxf(0.074,ThemeDB.fallback_font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size+0.014)
	label_hit_size=Vector2(width,0.022)
	_place_label()

func _place_label():
	# Position in screen space on the tip side, leaving the whole arrow exposed.
	# Refresh even when depth is unchanged: the viewer can walk around the part.
	var screen_right: Vector3=workbench.camera.global_basis.x.normalized()
	var side: float=-1 if direction.dot(screen_right)<-0.05 else 1
	var offset: float=label_hit_size.x/2+0.024
	var scale_: float=XRServer.world_scale
	label.global_position=tip_point+screen_right*side*offset*scale_
	label.scale=Vector3.ONE*scale_

func label_hit(hand: Node3D) -> bool:
	if not visible: return false
	var inverse:=Transform3D(workbench.camera.global_basis.orthonormalized(),label.global_position).affine_inverse()
	var from: Vector3=inverse*hand.global_position
	var ray: Vector3=inverse.basis*(-hand.global_basis.z.normalized())
	if absf(ray.z)<0.00001: return false
	var at: float=-from.z/ray.z
	var point:=from+ray*at
	return at>0 and absf(point.x)<label_hit_size.x*XRServer.world_scale/2 and absf(point.y)<label_hit_size.y*XRServer.world_scale/2

func hit(hand: Node3D) -> bool:
	if not visible: return false
	var from: Vector3=hand.global_position
	var ray: Vector3=-hand.global_basis.z.normalized()
	var at: float=(tip_point-from).dot(ray)
	if at<0: return false
	return (from+ray*at).distance_to(tip_point)<0.013*XRServer.world_scale
