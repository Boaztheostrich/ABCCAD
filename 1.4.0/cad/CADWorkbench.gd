extends Node3D
const Document = preload("res://cad/CADDocument.gd")
var command_wheel: Node3D
var hovered_region := ""
var document: Node3D
var enabled := true
var panel: Node3D
var panel_handles: Node3D
var dimension_drag: Node
var number_pad: Node3D
var _panel_stage_pose:=Transform3D.IDENTITY
var _panel_placed:=false
var ui: Control
var active_sketch := -1
var selected_regions: Array=[]
var _region_root:=-1
var _regions: Array=[]
var _regions_signature:=""
var _profile_signature:=""
var _profile_cache: Dictionary={}
var selected_body := -1
var selected_hit: Dictionary = {}
var tool := "select"
var angle_lines: Array=[]
var angle_sketch:=-1
var angle_pending: Dictionary={}
var depth_mm := 10.0
var operation := "New"
var message := "Select a face or start a sketch in front of you."
var hints := ""
var auto_constraints := true
var draw_node: MeshInstance3D
var marker: MeshInstance3D
var left: XRController3D
var right: XRController3D
var camera: XRCamera3D
var origin: XROrigin3D
var _triggers := [false,false]
var _back_buttons := [false,false]
var _drawing_hand: Node3D
var _chain_ended:=false
var _edge_hover_time:=0.0
var _edge_hover_valid:=false
var _project_candidates: Array=[]
var _project_groups: Dictionary={}
var _project_cache_valid:=false
var _project_hover_hits: Dictionary={}
var extrude_arrow: Node3D
var extrude_preview: Node3D
var face_highlight: MeshInstance3D
var sketch_visual: Node3D
var plane_visibility: Dictionary={"Front":true,"Top":true,"Right":true,"Sketch plane":true,"Table":true}
var sketch_visibility: Dictionary={}
var _zooming := false
var _zoom_distance := 0.0
var _zoom_scale := 1.0
var _zoom_pivot := Vector3.ZERO
var _zoom_origin := Vector3.ZERO
var _preview: Dictionary = {}
var _moving_origin := false
var plane_display: Node3D
var reference_display: Node3D
var probe_marker: MeshInstance3D
var contact_points: Array[Vector3]=[]
var probe_offset_mm:=Vector3(0,0,-70)
var table_view_scale:=1.0
var _table_zoom_start:=1.0
var _reference_signature:=""
var print_preview: Node
var print_display: MeshInstance3D
var print_enabled:=false
var print_loading:=false
var print_progress:=0.0
var _print_revision:=""
var _print_request:=0
const SETTINGS = "user://advanced_cad.cfg"

func _ready():
	add_to_group("cad_workbench")
	document = Document.new()
	document.name = "CADDocument"
	add_child(document)
	document.changed.connect(_changed)
	document.history_applied.connect(_conversion_history)
	document.history_guard=_can_apply_history
	document.status.connect(func(text): message=text; _refresh_ui())
	var cfg := ConfigFile.new()
	cfg.load(_settings_path())
	# Older versions used enabled=false as their default. Only an explicit
	# legacy-mode choice in this version opts out of the CAD-first startup.
	enabled = not bool(cfg.get_value("cad","legacy_mode",false))
	probe_offset_mm=cfg.get_value("cad","probe_offset_mm",Vector3(0,0,-70))
	left = get_parent().get_node("XROrigin3D/LeftHand")
	right = get_parent().get_node("XROrigin3D/RightHand")
	_drawing_hand=right
	origin = get_parent().get_node("XROrigin3D")
	camera = origin.get_node("XRCamera3D")
	reference_display=Node3D.new()
	add_child(reference_display)
	probe_marker=MeshInstance3D.new()
	var probe_sphere:=SphereMesh.new()
	probe_sphere.radius=0.004
	probe_sphere.height=0.008
	probe_marker.mesh=probe_sphere
	probe_marker.material_override=_line_material(Color("4e9eff"))
	add_child(probe_marker)
	probe_marker.visible=false
	print_preview=preload("res://cad/CADPrintPreview.gd").new()
	add_child(print_preview)
	print_preview.progress_changed.connect(func(value): print_progress=value; _refresh_ui())
	print_display=MeshInstance3D.new()
	print_display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(print_display)
	print_display.visible=false
	plane_display=Node3D.new()
	add_child(plane_display)
	face_highlight=preload("res://cad/CADFaceHighlight.gd").new()
	face_highlight.workbench=self
	add_child(face_highlight)
	draw_node = MeshInstance3D.new()
	add_child(draw_node)
	marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.002
	sphere.height = 0.004
	marker.mesh = sphere
	marker.material_override = _line_material(Color("ffcb72"))
	add_child(marker)
	marker.visible = false
	sketch_visual=preload("res://cad/CADSketchVisual.gd").new()
	sketch_visual.workbench=self
	add_child(sketch_visual)
	panel = preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn").instantiate()
	panel.name = "CADPanel"
	panel.screen_size = Vector2(0.90,0.75)
	panel.viewport_size = Vector2(1120,900)
	panel.scene = preload("res://cad/CADPanel.tscn")
	panel.collision_layer = 5242880
	panel.unshaded = true
	var ui_material:=StandardMaterial3D.new()
	ui_material.no_depth_test=true
	ui_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	ui_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ui_material.render_priority=120
	panel.material=ui_material
	add_child(panel)
	panel.visible = false
	panel_handles=preload("res://cad/CADPanelHandles.gd").new()
	panel_handles.workbench=self
	panel_handles.panel=panel
	panel.add_child(panel_handles)
	ui = panel.get_node("Viewport").get_child(0)
	ui.workbench = self
	dimension_drag=preload("res://cad/CADDimensionDrag.gd").new()
	dimension_drag.workbench=self
	add_child(dimension_drag)
	number_pad=preload("res://cad/CADNumberPad.gd").new()
	number_pad.workbench=self
	add_child(number_pad)
	extrude_arrow=preload("res://cad/CADExtrudeArrow.gd").new()
	extrude_arrow.workbench=self
	add_child(extrude_arrow)
	extrude_preview=preload("res://cad/CADExtrudePreview.gd").new()
	extrude_preview.workbench=self
	add_child(extrude_preview)
	command_wheel=preload("res://cad/CADCommandWheel.gd").new()
	command_wheel.workbench=self
	add_child(command_wheel)
	SignalBus.request_toggle_menu.connect(func():
		if panel.visible: close_panel())

func set_enabled(value: bool):
	enabled = value
	var cfg := ConfigFile.new()
	cfg.load(_settings_path())
	cfg.set_value("cad","legacy_mode",not value)
	cfg.set_value("cad","enabled",value)
	cfg.save(_settings_path())
	if not value:
		set_print_preview(false)
		close_panel()
		reset_view()
	_refresh_ui()

func is_modeling() -> bool:
	return enabled and panel != null and panel.visible

func open_panel():
	if not enabled: return
	var tutorial=get_parent().get_node_or_null("tutorial screen")
	if tutorial: tutorial._on_tutorial_closed(false)
	var menu = get_parent().get_node("Viewport2Din3D")
	if menu.visible: SignalBus.request_toggle_menu.emit()
	panel.visible = true
	_place_panel()
	_pointers(true)
	_refresh_ui()
	_redraw()
	_redraw_reference()

func close_panel():
	if dimension_drag and dimension_drag.hand: dimension_drag.end(true)
	_moving_origin=false
	if ui: ui.keypad.visible=false
	if ui and ui.confirmation: ui.cancel_confirmation()
	panel_handles.cancel()
	extrude_arrow.end_drag(true)
	extrude_preview.cancel()
	panel.visible = false
	marker.visible = false
	if draw_node: draw_node.visible = false
	if sketch_visual: sketch_visual.visible=false
	if face_highlight: face_highlight.visible=false
	if extrude_arrow: extrude_arrow.visible=false
	if plane_display: plane_display.visible=false
	_zooming = false
	if reference_display: reference_display.visible=false
	if probe_marker: probe_marker.visible=false
	_pointers(get_parent().get_node("Viewport2Din3D").visible)

func _pointers(value: bool):
	for hand in [left,right]:
		var pointer = hand.get_node(str(hand.name)+"/FunctionPointer")
		pointer.enabled = value
		pointer.visible = value
		pointer.set_process(value)

## Scene lighting controls are presentation settings, independent of CAD history.
func scene_lights() -> Array:
	var lights: Array=[]
	var labels: Dictionary={
		"OmniLight3D5":"Front",
		"OmniLight3D4":"Left",
		"OmniLight3D2":"Right",
		"OmniLight3D":"Origin light 1",
		"OmniLight3D3":"Origin light 2",
		"DirectionalLight3D":"Main directional light",
	}
	for name_ in labels:
		var light=get_parent().get_node_or_null(NodePath(name_))
		if light is Light3D:
			lights.append({"name":name_,"label":labels[name_],"enabled":light.visible})
	return lights

func toggle_scene_light(name_: String):
	# Only expose the known scene lights, never arbitrary scene nodes.
	for item in scene_lights():
		if item.name==name_:
			var light: Light3D=get_parent().get_node(NodePath(name_))
			light.visible=not light.visible
			_refresh_ui()
			return

func face_sketch_plane(hit: Dictionary) -> Transform3D:
	var normal: Vector3=hit.normal.normalized()
	# Tiny triangles left by earlier booleans make a noisy plane normal.
	# Use the largest triangle on the same surface for a stable face frame.
	var source_faces: Array=hit.source.get("faces",document.body(int(hit.source.id)).get("faces",[]))
	var largest:=0.0
	var surface_point: Vector3=hit.point_mm
	for i in range(0,source_faces.size(),3):
		var vertices: Array=[]
		for j in 3:
			var v: Array=source_faces[i+j];vertices.append(Vector3(v[0],v[1],v[2]))
		if vertices.any(func(p):return absf(hit.normal.dot(p-hit.point_mm))>0.02): continue
		var cross: Vector3=(vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
		if cross.length_squared()<=largest or absf(cross.normalized().dot(hit.normal))<0.999: continue
		largest=cross.length_squared()
		normal=cross.normalized()*(-1 if cross.dot(hit.normal)<0 else 1)
		surface_point=vertices[0]
	var preferred: Array=[Vector3.UP,Vector3.BACK,Vector3.RIGHT]
	var body: Dictionary=document.body(int(hit.source.id))
	# A face sketch uses the part's frame, including its placement rotation,
	# rather than inventing a new world-up roll after the part was grabbed.
	if not body.is_empty() and not body.get("features",[]).is_empty():
		var basis:=Document.unpack_transform(body.features[0].sketch.plane).basis
		preferred=[basis.y,basis.z,basis.x]
	elif is_instance_valid(hit.source.get("block")):
		var basis: Basis=hit.source.block.global_basis.orthonormalized()
		preferred=[basis.y,basis.z,basis.x]
	var y:=Vector3.UP
	for axis in preferred:
		var projected: Vector3=axis-normal*axis.dot(normal)
		if projected.length()>0.1: y=projected.normalized(); break
	var at: Vector3=document.origin_mm-normal*(document.origin_mm-surface_point).dot(normal)
	var basis:=Basis(y.cross(normal).normalized(),y,normal).orthonormalized()
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	var face_hit:=hit.duplicate()
	face_hit.source=hit.source.duplicate()
	face_hit.source.faces=source_faces
	face_hit.normal=normal
	face_hit.point_mm=at
	for edge in preload("res://cad/CADFaceEdges.gd").boundary(face_hit):
		for p in edge:
			var local: Vector3=basis.inverse()*p
			low=low.min(local);high=high.max(local)
	if low.is_finite(): at=basis*((low+high)/2)
	return Transform3D(basis,at)

func new_sketch(on_face: bool = false):
	if document.busy: return
	var plane := Transform3D.IDENTITY
	var body_id := -1
	if on_face:
		if selected_hit.is_empty(): message="Aim at a face and pull trigger first."; _refresh_ui(); return
		var source: Dictionary=selected_hit.source
		if int(source.id)>=0 and document.body(int(source.id)).get("faces",[])!=source.faces:
			message="Select the face again after editing or moving the body."; _refresh_ui(); return
		plane = face_sketch_plane(selected_hit)
		body_id = selected_body
	else:
		plane = document.base_plane("Front")
	active_sketch = document.new_sketch(plane,body_id)
	plane_visibility["Sketch plane"]=true
	tool = "line"
	_chain_ended=false
	message = "Line · click start, preview, click next point. B ends the chain."
	_changed()

func choose_tool(value: String):
	if document.busy: return
	tool = value
	if value != "select" and document.sketch(active_sketch).is_empty(): new_sketch()
	var current: Dictionary=document.sketch(active_sketch)
	var drawing_on_projection: bool=value=="line" and current.get("closed_by_projection",false) and current.get("points",[]).is_empty()
	if value in ["line","circle","rectangle"] and not current.get("points",[]).is_empty() and ((current.get("closed",false) and not drawing_on_projection) or _chain_ended or current.kind!=value):
		active_sketch=document.new_entity(active_sketch,value)
	_chain_ended=false
	if value in ["line","circle","rectangle"]:
		for entity in document.sketch_members(active_sketch):sketch_visibility[int(entity.id)]=true
		plane_visibility["Sketch plane"]=true
	tool = value
	message = {"line":"Line · click start, preview, click next. B ends the chain.","rectangle":"Center rectangle · center, then corner.","circle":"Circle · center, then radius point.","select":"Select · trigger a face to attach a sketch or convert its edges."}.get(value,"")
	_redraw()
	_refresh_ui()

func resume_lines():
	var s: Dictionary=document.sketch(active_sketch)
	if document.busy or s.is_empty() or s.kind!="line" or s.closed: return
	tool="line"; _chain_ended=false
	for entity in document.sketch_members(active_sketch):sketch_visibility[int(entity.id)]=true; plane_visibility["Sketch plane"]=true
	message="Continue Sketch %d from its last endpoint." % active_sketch
	_redraw(); _refresh_ui()

func start_use_edge():
	if document.busy or document.sketch(active_sketch).is_empty(): return
	tool="use_edge"; _chain_ended=false
	_edge_hover_time=1.0; _edge_hover_valid=false
	message="Project · aim at a face edge, trigger to copy it. Keep selecting edges; B finishes."
	_project_cache_valid=false; _project_hover_hits.clear()
	_refresh_ui()

func start_extend_vertex():
	var s: Dictionary=document.sketch(active_sketch)
	if document.busy or s.is_empty() or s.kind!="line" or s.points.is_empty(): return
	tool="extend_vertex"
	message="Trigger an existing sketch vertex to start a connected new chain. The original profile is kept."
	_refresh_ui()

func extend_vertex(point: Vector2) -> bool:
	var s: Dictionary=document.sketch(active_sketch)
	if document.busy or s.is_empty() or s.kind!="line": return false
	var closest:=_snap_tolerance(); var index:=-1
	for i in s.points.size():
		var distance: float=point.distance_to(Vector2(s.points[i][0],s.points[i][1]))
		if distance<closest: closest=distance; index=i
	if index<0: return false
	var target: int=int(s.id)
	active_sketch=document.new_entity(active_sketch,"line")
	document.set_profile(active_sketch,"line",[s.points[index].duplicate()],false)
	document.add_inference(active_sketch,0,{"kind":"coincident","target":target,"index":index})
	tool="line"; _chain_ended=false; _changed()
	return true

func edge_hit(hand: Node3D) -> Dictionary:
	var s: Dictionary=document.sketch(active_sketch)
	if s.is_empty(): return {}
	var body: Dictionary=document.body(int(s.body_id))
	if body.is_empty(): return _uncached_edge_hit(hand)
	var plane:=Document.unpack_transform(s.plane)
	if not _project_cache_valid:
		_project_candidates.clear()
		_project_groups.clear()
		var hit: Dictionary={"normal":plane.basis.z,"point_mm":plane.origin,"source":{"faces":body.faces}}
		var inverse:=plane.affine_inverse()
		for edge in preload("res://cad/CADFaceEdges.gd").boundary(hit):
			var a: Vector3=inverse*edge[0];var b: Vector3=inverse*edge[1]
			_project_candidates.append([Vector2(a.x,a.y),Vector2(b.x,b.y)])
		_project_cache_valid=true
	var hit:=_plane_point(hand)
	if hit.is_empty(): return {}
	var raw: Vector2=hit.point
	var nearest:=_snap_tolerance()
	var result: Dictionary={}
	for edge in _project_candidates:
		var cursor:=Geometry2D.get_closest_point_to_segment(raw,edge[0],edge[1])
		var distance: float=cursor.distance_to(raw)
		if distance<nearest:
			nearest=distance;result={"points":edge,"body":int(body.id),"cursor":cursor}
	if not result.is_empty():
		if not _project_groups.has(result.points):
			var group: Array=preload("res://cad/CADFaceEdges.gd").projection_group(_project_candidates,result.points)
			for segment in group: _project_groups[segment]=group
		result.edges=_project_groups[result.points]
	return result

func _uncached_edge_hit(hand: Node3D) -> Dictionary:
	var s: Dictionary=document.sketch(active_sketch)
	if s.is_empty(): return {}
	hand=_ray_node(hand)
	var hit:=_face_hit(hand.global_position,-hand.global_basis.z.normalized())
	if hit.is_empty(): return {}
	var nearest: float=30.0*XRServer.world_scale/document.view_transform.basis.x.length()
	var chosen: Array=[]
	for edge in preload("res://cad/CADFaceEdges.gd").boundary(hit):
		var closest:=Geometry3D.get_closest_point_to_segment(hit.point_mm,edge[0],edge[1])
		var distance: float=closest.distance_to(hit.point_mm)
		if distance<nearest: nearest=distance; chosen=edge
	if chosen.is_empty(): return {}
	var inverse:=Document.unpack_transform(s.plane).affine_inverse()
	var points: Array=[]
	for p in chosen:
		var model: Vector3=p
		if int(hit.source.id)<0: model=document.view_transform.affine_inverse()*(p*0.001)*1000
		var local: Vector3=inverse*model
		points.append(Vector2(local.x,local.y))
	if points[0].distance_to(points[1])<0.01: return {}
	# Continue from the end nearer the laser, so selecting an endpoint feels natural.
	var local_hit: Vector3=inverse*(hit.point_mm if int(hit.source.id)>=0 else document.view_transform.affine_inverse()*(hit.point_mm*0.001)*1000)
	if points[0].distance_to(Vector2(local_hit.x,local_hit.y))<points[1].distance_to(Vector2(local_hit.x,local_hit.y)): points.reverse()
	var local_edges: Array=[]
	for edge in preload("res://cad/CADFaceEdges.gd").boundary(hit):
		var pair: Array=[]
		for p in edge:
			var model: Vector3=p
			if int(hit.source.id)<0: model=document.view_transform.affine_inverse()*(p*0.001)*1000
			var local: Vector3=inverse*model
			pair.append(Vector2(local.x,local.y))
		local_edges.append(pair)
	return {"points":points,"edges":preload("res://cad/CADFaceEdges.gd").projection_group(local_edges,points),"body":int(hit.source.id),"cursor":Geometry2D.get_closest_point_to_segment(Vector2(local_hit.x,local_hit.y),points[0],points[1])}


func use_edge(edge: Dictionary) -> bool:
	var s: Dictionary=document.sketch(active_sketch)
	if document.busy or s.is_empty() or edge.is_empty(): return false
	var added: bool=document.add_projected_edges(active_sketch,edge.get("edges",[edge.points]))
	if not added:
		message="That edge is already projected. Select another edge, or B to finish."
		return false
	if int(s.body_id)<0 and int(edge.get("body",-1))>=0: s.body_id=int(edge.body)
	tool="use_edge"; _chain_ended=false
	for entity in document.sketch_members(active_sketch):sketch_visibility[int(entity.id)]=true
	message="Project · %d edges in this sketch. Select another edge; B finishes." % s.projected_edges.size()
	_changed()
	return true

func close_profile():
	var s: Dictionary = document.sketch(active_sketch)
	if s.is_empty() or s.points.size()<3 or s.kind!="line": return
	document.set_profile(active_sketch,s.kind,s.points,true)
	message="Closed profile. Set depth and choose New, Add, or Remove."
	_refresh_ui()

func reverse_extrude_direction():
	if document.busy: return
	depth_mm=-depth_mm
	message="Extrude direction reversed · %+.2f mm. Check the arrow before Apply." % depth_mm
	_refresh_ui()

func regions() -> Array:
	var root: int=document.sketch_root(active_sketch)
	var signature:=str(document.entity_geometry(document.sketch_members(active_sketch)))
	if root!=_region_root or signature!=_regions_signature:
		var same_group:=root==_region_root
		_region_root=root;_regions_signature=signature
		_regions=document.sketch_regions(active_sketch)
		var available: Array=_regions.map(func(r):return r.id)
		selected_regions=selected_regions.filter(func(id):return id in available) if same_group and ui.mode=="extrude" else []
		if _regions.size()==1:selected_regions=[_regions[0].id]
	return _regions

func selected_profile() -> Dictionary:
	regions()
	var signature:=str([_regions_signature,selected_regions])
	if signature!=_profile_signature:
		_profile_signature=signature
		_profile_cache=document.region_profile(active_sketch,selected_regions,_regions)
	return _profile_cache

func begin_region_selection():
	tool="select"
	var areas:=regions()
	for entity in document.sketch_members(active_sketch):sketch_visibility[int(entity.id)]=true
	plane_visibility["Sketch plane"]=true
	message="No enclosed areas yet. Close a profile in this sketch." if areas.is_empty() else "One area selected automatically." if areas.size()==1 else "Please select the area or areas you want to extrude."
	_redraw()

func select_region(at: Vector2) -> bool:
	for region in regions():
		if preload("res://cad/CADSketchRegions.gd").contains(region,at):
			if region.id in selected_regions:selected_regions.erase(region.id)
			else:selected_regions.append(region.id)
			message="%d area%s selected." % [selected_regions.size(),"" if selected_regions.size()==1 else "s"] if not selected_regions.is_empty() else "Please select the area or areas you want to extrude."
			_redraw();_refresh_ui();return true
	return false

func extrude() -> bool:
	if document.busy: return false
	regions()
	if selected_regions.is_empty():message="Please select the area or areas you want to extrude.";_refresh_ui();return false
	var success: bool=await document.extrude_regions(active_sketch,selected_regions,depth_mm,operation,selected_body if operation!="New" else -1)
	if success:
		for entity in document.sketch_members(active_sketch):sketch_visibility[int(entity.id)]=false
		plane_visibility["Sketch plane"]=false
		selected_hit={}
		selected_body = int(document.sketch(active_sketch).body_id)
		tool = "select"
	_changed()
	return success

func _changed():
	_profile_signature=""
	if tool=="angle" and active_sketch!=angle_sketch:
		tool="select";angle_lines.clear();angle_pending={}
	_project_cache_valid=false
	_project_hover_hits.clear()
	if not document.sketch(active_sketch).is_empty():
		var owner_id: int=int(document.sketch(active_sketch).body_id)
		if owner_id>=0: selected_body=owner_id
	elif not document.sketches.is_empty(): active_sketch = int(document.sketches[-1].id)
	else: active_sketch = -1
	if not document.body(selected_body).is_empty(): pass
	else: selected_body = -1
	_update_reference_view()
	_redraw()
	_redraw_reference()
	_update_print_preview()
	_refresh_ui()

func _drag_origin(hand: Node3D):
	var inverse: Transform3D=document.view_transform.affine_inverse()
	var position_mm: Vector3=(inverse*(hand.global_position-hand.global_basis.z*0.25))*1000.0
	var toward: Vector3=inverse*camera.global_position-position_mm*0.001
	# Flatten the view direction: headset pitch and roll must never tilt Top.
	toward.y=0.0
	var yaw: float=document.origin_yaw
	if toward.length_squared()>0.0001: yaw=atan2(toward.x,toward.z)
	document.move_origin(position_mm,false,yaw)

func _refresh_ui():
	if ui and ui.has_method("refresh"): ui.refresh()
	if extrude_arrow: extrude_arrow.refresh()

func _process(_delta):
	_update_panel_pose()
	_update_reference_view()
	if extrude_arrow: extrude_arrow.refresh()
	if extrude_preview: extrude_preview.refresh(_delta)
	print_display.transform=document.view_transform
	if sketch_visual: sketch_visual.transform=document.view_transform
	if face_highlight and not selected_hit.is_empty() and int(selected_hit.source.id)>=0: face_highlight.transform=document.view_transform
	if not is_modeling():
		probe_marker.visible=false
		return
	_update_region_hover()
	if extrude_arrow.drag_hand==null and dimension_drag.hand==null and not ui.keypad.visible: _zoom()
	elif ui.keypad.visible: _zooming=false
	var hands := [left,right]
	for index in 2:
		var hand: XRController3D = hands[index]
		if not hand.get_is_active():
			if dimension_drag.hand==_ray_node(hand): dimension_drag.end(true)
			number_pad.cancel_drag(_ray_node(hand))
			if index==1: _moving_origin=false
			if extrude_arrow.drag_hand==_ray_node(hand): extrude_arrow.end_drag(true)
			_triggers[index]=false
			continue
		var back:=hand.is_button_pressed("by_button")
		if back and not _back_buttons[index]: end_sketch_tool()
		_back_buttons[index]=back
		var pressed := hand.is_button_pressed("trigger_click")
		var ray_hand:=_ray_node(hand)
		if dimension_drag.hand:
			if dimension_drag.hand==ray_hand:
				if back or document.busy or ui.confirmation.visible: dimension_drag.end(true)
				elif pressed: dimension_drag.update()
				else: dimension_drag.end()
			_triggers[index]=pressed
			continue
		# A world drag owns its trigger through release, including over UI handles.
		if index==1 and _moving_origin:
			if pressed: _drag_origin(hand)
			else: _moving_origin=false
			_triggers[index]=pressed
			continue
		if extrude_arrow.drag_hand==ray_hand:
			if back: extrude_arrow.end_drag(true)
			elif pressed: extrude_arrow.update_drag(ray_hand)
			else: extrude_arrow.end_drag()
			_triggers[index]=pressed
			continue
		if extrude_arrow.drag_hand!=null:
			_triggers[index]=pressed
			continue
		if number_pad.handle_input(ray_hand,pressed,pressed and not _triggers[index]) or ui.keypad.visible:
			_triggers[index]=pressed
			continue
		if pressed and not _triggers[index] and not _zooming and not _ray_hits_panel(hand) and not ui.confirmation.visible and dimension_drag.begin(ray_hand):
			_triggers[index]=pressed
			continue
		if pressed and not _triggers[index] and not _zooming and not _ray_hits_panel(hand) and not ui.confirmation.visible and extrude_arrow.begin_drag(ray_hand):
			_triggers[index]=pressed
			continue
		if panel_handles.handle_input(_ray_node(hand),pressed,pressed and not _triggers[index]):
			_triggers[index]=pressed
			continue
		if tool=="capture_plane":
			if pressed and not _triggers[index] and not _ray_hits_panel(hand): capture_contact(hand)
		elif tool=="origin" and index==1 and not _ray_hits_panel(hand):
			if pressed and not _triggers[index]:
				document.checkpoint()
				_moving_origin=true
			if pressed and _moving_origin:
				_drag_origin(hand)
			if not pressed: _moving_origin=false
		elif pressed and not _triggers[index] and not _zooming and not document.busy:
			if not _ray_hits_panel(hand):
				_drawing_hand=hand
				_world_click(hand)
		_triggers[index] = pressed
	probe_marker.visible=tool=="capture_plane" or (ui.mode=="table" and ui.probe_settings)
	if probe_marker.visible:
		probe_marker.global_position=probe_point(right)
		probe_marker.scale=Vector3.ONE*XRServer.world_scale
	if tool in ["line","circle","rectangle"] and not document.sketch(active_sketch).is_empty() and not document.sketch(active_sketch).closed:
		_preview = _plane_point(_drawing_hand)
		marker.visible = not _preview.is_empty() and not _ray_hits_panel(_drawing_hand)
		if marker.visible:
			var s: Dictionary = document.sketch(active_sketch)
			var inferred: Dictionary = _infer_point(active_sketch,_preview.point, _snap_tolerance())
			_preview.point = inferred.point
			hints = inferred.get("label","")
			var p: Vector2 = inferred.point
			marker.global_position = document.view_transform*(Document.unpack_transform(s.plane)*Vector3(p.x,p.y,0)*0.001)
			marker.scale = Vector3.ONE*XRServer.world_scale*document.view_transform.basis.x.length()
			ui.set_hint(hints)
			sketch_visual.update_preview(s,p,true)
			sketch_visual.update_guides(inferred.get("guides",[]),Document.unpack_transform(s.plane))
		else: sketch_visual.update_preview({},Vector2.ZERO,false)
	else:
		marker.visible = false
		sketch_visual.update_preview({},Vector2.ZERO,false)
	if tool=="angle":
		var s: Dictionary=document.sketch(active_sketch)
		var hit:=_plane_point(_drawing_hand)
		if not s.is_empty():
			var c: Dictionary=angle_pending
			if not c.is_empty() and not hit.is_empty() and not _ray_hits_panel(_drawing_hand): c=preload("res://cad/CADAngleDimension.gd").placed(s,c,hit.point)
			var segments: Array=[]
			for index in angle_lines: segments.append([s.points[index],s.points[(index+1)%s.points.size()]])
			if c.is_empty() and not hit.is_empty():
				var index:=angle_line_at(hit.point)
				if index>=0: segments.append([s.points[index],s.points[(index+1)%s.points.size()]])
			sketch_visual.update_angle(s,c,segments)
	if tool=="use_edge":
		sketch_visual.guides.visible=_edge_hover_valid
		_edge_hover_time+=_delta
		if _edge_hover_time>=(0.0 if _project_cache_valid and _project_candidates.size()<=128 else 0.05):
			_edge_hover_time=0; _project_hover_hits.clear()
			var segments: Array=[]
			for controller in [left,right]:
				var ray:=_ray_node(controller)
				if _ray_hits_panel(ray): continue
				var edge:=edge_hit(ray)
				if edge.is_empty(): continue
				_project_hover_hits[ray.get_instance_id()]=edge
				segments.append_array(edge.get("edges",[edge.points]))
			_edge_hover_valid=not segments.is_empty()
			var current: Dictionary=document.sketch(active_sketch)
			if not current.is_empty(): sketch_visual.update_project_highlight(segments,Document.unpack_transform(current.plane))

func _ray_hits_panel(hand: Node3D) -> bool:
	hand=_ray_node(hand)
	if number_pad and not number_pad.intersection(hand).is_empty(): return true
	var inverse := panel.global_transform.affine_inverse()
	var p: Vector3 = inverse*hand.global_position
	var d: Vector3 = inverse.basis*(-hand.global_basis.z)
	if absf(d.z)<0.00001: return false
	var t := -p.z/d.z
	var hit := p+d*t
	return t>0 and absf(hit.x)<=panel.screen_size.x/2 and absf(hit.y)<=panel.screen_size.y/2

func _plane_point(hand: Node3D,quantize: bool=true) -> Dictionary:
	hand=_ray_node(hand)
	var s: Dictionary = document.sketch(active_sketch)
	if s.is_empty(): return {}
	var inverse := Document.unpack_transform(s.plane).affine_inverse()
	var p: Vector3 = inverse*((document.view_transform.affine_inverse()*hand.global_position)*1000)
	var d: Vector3 = inverse.basis*(document.view_transform.basis.inverse()*(-hand.global_basis.z))
	if absf(d.z)<0.00001: return {}
	var t := -p.z/d.z
	if t<0 or t>20000: return {}
	var point := p+d*t
	return {"point":Vector2(snappedf(point.x,0.1),snappedf(point.y,0.1)) if quantize else Vector2(point.x,point.y)}

func _world_click(hand: Node3D):
	if ui.confirmation.visible: return
	hand=_ray_node(hand)
	if extrude_arrow.label_hit(hand):
		ui.edit_number("depth",extrude_arrow.label.global_position)
		return
	if extrude_arrow.hit(hand):
		reverse_extrude_direction()
		return
	if ui.mode=="extrude":
		var point:=_plane_point(hand,false)
		if not point.is_empty():select_region(point.point)
		return
	if tool=="use_edge":
		var edge:=edge_hit(hand)
		if edge.is_empty(): message="Aim near an edge on this face."
		else: use_edge(edge)
		_refresh_ui()
		return
	if tool=="angle":
		var hit:=_plane_point(hand)
		if not hit.is_empty(): angle_click(hit.point)
		return
	if tool=="extend_vertex":
		var point:=_plane_point(hand)
		if not point.is_empty(): extend_vertex(point.point)
		return
	if tool=="plane_select":
		var plane_name:=pick_base_plane(hand)
		if not plane_name.is_empty(): new_base_sketch(plane_name)
		return
	if tool=="select":
		var dimension: Dictionary=sketch_visual.hit_dimension(hand)
		if not dimension.is_empty():
			active_sketch=int(dimension.sketch)
			ui.show_command("sketch")
			var at: Vector3=dimension.plane*Vector3(dimension.point.x,dimension.point.y,0)
			ui.edit_number(dimension.field,document.view_transform*(at*0.001))
			return
	if tool == "select":
		select_face(hand.global_position,-hand.global_basis.z)
		return
	var hit := _plane_point(hand)
	if hit.is_empty(): return
	var s: Dictionary = document.sketch(active_sketch)
	var inferred: Dictionary = _infer_point(active_sketch,hit.point,_snap_tolerance())
	var p: Vector2 = inferred.point
	var points: Array = s.points.duplicate(true)
	if s.kind != tool or (s.closed and tool != "line"):
		points = []
	if tool == "line" and s.closed: points=[]
	if not points.is_empty() and p.distance_to(Vector2(points[-1][0],points[-1][1]))<0.01: return
	points.append([p.x,p.y])
	var close := tool!="line" and points.size()==2
	var closing_to_first := false
	if tool=="line" and points.size()>3 and p.distance_to(Vector2(points[0][0],points[0][1]))<0.01:
		points.pop_back()
		close = true
		closing_to_first = true
	document.set_profile(active_sketch,tool,points,close)
	close=document.sketch(active_sketch).closed
	if not closing_to_first:
		document.add_inference(active_sketch,points.size()-1,inferred.get("constraint",{}))
	close=document.sketch(active_sketch).closed
	if close: tool="select"
	message = inferred.get("label","") if not close else "Closed profile · select dimensions to define it, then Extrude."
	_changed()

func _face_hit(ray_origin: Vector3, direction: Vector3) -> Dictionary:
	var closest := INF
	var result: Dictionary={}
	var sources: Array = []
	for b in document.bodies: sources.append({"id":int(b.id),"faces":b.faces,"block":null})
	var seen := {}
	for pos in VoxelDatabase.get_all_voxels():
		var obj := VoxelDatabase.get_voxel(pos)
		if not is_instance_valid(obj) or seen.has(obj): continue
		seen[obj] = true
		var instance = obj.get_node_or_null("MeshInstance3D")
		if instance and instance.mesh:
			var faces: Array = []
			for v in instance.mesh.get_faces():
				var p: Vector3 = instance.global_transform*v*1000
				faces.append([p.x,p.y,p.z])
			sources.append({"id":-1,"faces":faces,"block":obj})
	for source in sources:
		var faces: Array = source.faces
		var display: Transform3D=document.view_transform if int(source.id)>=0 else Transform3D.IDENTITY
		var inverse_display:=display.affine_inverse()
		var model_ray: Vector3=inverse_display*ray_origin
		var model_direction: Vector3=(inverse_display.basis*direction).normalized()
		for i in range(0,faces.size(),3):
			var a := Vector3(faces[i][0],faces[i][1],faces[i][2])
			var b := Vector3(faces[i+1][0],faces[i+1][1],faces[i+1][2])
			var c := Vector3(faces[i+2][0],faces[i+2][1],faces[i+2][2])
			var hit = Geometry3D.ray_intersects_triangle(model_ray*1000.0,model_direction,a,b,c)
			if hit == null: continue
			var distance: float = ray_origin.distance_to(display*(hit*0.001))
			if distance<closest:
				closest = distance
				var normal := (b-a).cross(c-a).normalized()
				if normal.dot(model_direction)>0: normal=-normal
				# Preserve the exact source plane in mm rather than round-tripping
				# the hit through meter-space float tracking coordinates.
				var source_vertex:=Vector3(faces[i][0],faces[i][1],faces[i][2])
				var hit_mm: Vector3=hit
				hit_mm-=normal*(hit_mm-source_vertex).dot(normal)
				result = {"point":display*(hit*0.001),"point_mm":hit_mm,"normal":normal,"source":source,"triangle":i}
	return result

func select_face(ray_origin: Vector3, direction: Vector3):
	selected_hit=_face_hit(ray_origin,direction)
	selected_body=int(selected_hit.source.id) if not selected_hit.is_empty() else -1
	_redraw_selection()
	message="Face selected · Sketch on face or Convert face edges." if not selected_hit.is_empty() else "Selection cleared."
	_refresh_ui()

func convert_edges():
	if selected_hit.is_empty(): message="Select a planar face first."; _refresh_ui(); return
	new_sketch(true)
	var s: Dictionary = document.sketch(active_sketch)
	var inverse := Document.unpack_transform(s.plane).affine_inverse()
	var faces: Array = selected_hit.source.faces
	var edges := {}
	var vertices := {}
	for i in range(0,faces.size(),3):
		var points: Array = []
		for j in 3:
			var v: Array = faces[i+j]
			points.append(inverse*Vector3(v[0],v[1],v[2]))
		if points.any(func(v): return absf(v.z)>0.02): continue
		for j in 3:
			var a: Vector3 = points[j]
			var b: Vector3 = points[(j+1)%3]
			var ka := "%.3f,%.3f" % [a.x,a.y]
			var kb := "%.3f,%.3f" % [b.x,b.y]
			var key := ka+"/"+kb if ka<kb else kb+"/"+ka
			edges[key] = int(edges.get(key,0))+1
			vertices[ka] = [a.x,a.y]
			vertices[kb] = [b.x,b.y]
	var boundary: Array = []
	for edge in edges:
		if edges[edge]==1: boundary.append(edge.split("/"))
	if boundary.is_empty(): message="No planar boundary found."; _refresh_ui(); return
	var loop: Array = [boundary[0][0]]
	var current: String = boundary[0][1]
	boundary.remove_at(0)
	while current != loop[0] and loop.size()<10000:
		loop.append(current)
		var found := false
		for i in boundary.size():
			if current in boundary[i]:
				current = boundary[i][1] if boundary[i][0]==current else boundary[i][0]
				boundary.remove_at(i)
				found = true
				break
		if not found: break
	if current!=loop[0] or not boundary.is_empty(): message="This MVP converts one simple face boundary at a time (no inner loops)."; _refresh_ui(); return
	var profile: Array = []
	for key in loop: profile.append(vertices[key])
	document.set_profile(active_sketch,"line",profile,true)
	tool="line"
	message="Converted planar face boundary to a closed line profile."
	_changed()

func promote_selected_block():
	if selected_hit.is_empty() or selected_hit.source.block == null: return
	var source: Dictionary = selected_hit.source
	var block: Node3D = source.block
	document.checkpoint()
	var id: int = document.next_id
	document.next_id += 1
	var mesh=block.get_node("MeshInstance3D")
	var cells: Array=[]
	for pos in VoxelDatabase.get_all_voxels():
		if VoxelDatabase.get_voxel(pos)==block: cells.append([pos.x,pos.y,pos.z])
	var master:=Vector3i.ZERO
	for pos in VoxelDatabase.get_all_voxels():
		var data=VoxelDatabase.get_voxel_data(pos)
		if data.object==block and data.is_master: master=pos; break
	var converted: Dictionary={"shape":block.get_meta("shape_type","cube"),"transform":Document.pack_transform(block.global_transform),"color":mesh.get_color().to_html(),"grid":[master.x,master.y,master.z],"cells":cells}
	document.bodies.append({"id":id,"name":"Converted block","faces":source.faces.duplicate(true),"features":[],"base_faces":source.faces.duplicate(true),"converted_source":converted})
	for pos in VoxelDatabase.get_all_voxels():
		if VoxelDatabase.get_voxel(pos)==block: VoxelDatabase.remove_voxel(pos,true,true); break
	# Conversion crosses from block history into CAD history. The old placement
	# entries must not later respawn a duplicate underneath the converted solid.
	VoxelDatabase.undo_stack.clear()
	VoxelDatabase.redo_stack.clear()
	selected_body=id
	selected_hit.source.id=id
	selected_hit.source.block=null
	if active_sketch!=-1:
		for entity in document.sketch_members(active_sketch):entity.body_id=id
	document.rebuild_visuals()
	message="Block converted to a CAD body. Sketch on its face to Add or Remove."
	_changed()

func _redraw():
	if not draw_node: return
	_redraw_planes()
	draw_node.mesh=null
	if sketch_visual: sketch_visual.redraw()
	_redraw_selection()

func _redraw_selection():
	if not face_highlight: return
	if not selected_hit.is_empty() and int(selected_hit.source.id)>=0:
		var current: Dictionary=document.body(int(selected_hit.source.id))
		if current.is_empty() or current.faces!=selected_hit.source.faces: selected_hit={}
	face_highlight.rebuild(selected_hit,document.view_transform)
	face_highlight.visible=is_modeling() and not selected_hit.is_empty()

func toggle_plane_visibility(name_: String):
	plane_visibility[name_]=not plane_visibility.get(name_,true)
	_redraw()
	_redraw_reference()
	_refresh_ui()

func toggle_sketch_visibility(id: int):
	var shown: bool=not sketch_visibility.get(document.sketch_root(id),true)
	for entity in document.sketch_members(id):sketch_visibility[int(entity.id)]=shown
	if document.sketch_root(id)==document.sketch_root(active_sketch) and not shown and tool in ["line","circle","rectangle"]: tool="select"
	_redraw()
	_refresh_ui()

func _ray_node(hand: Node3D) -> Node3D:
	if hand is XRController3D:
		var pointer=hand.get_node_or_null(str(hand.name)+"/FunctionPointer")
		if pointer: return pointer
	return hand

func pointer_ui_bodies() -> Array[CollisionObject3D]:
	var bodies: Array[CollisionObject3D]=[]
	for body in panel.find_children("*","CollisionObject3D",true,false): bodies.append(body)
	if number_pad and number_pad.panel.visible:
		bodies.append(number_pad.panel.get_node("StaticBody3D"))
	return bodies

func world_drag_active(hand: Node3D) -> bool:
	if not is_modeling(): return false
	var ray:=_ray_node(hand)
	if _moving_origin and ray==_ray_node(right): return true
	if extrude_arrow.drag_hand==ray: return true
	for controller in [left,right]:
		if ray==_ray_node(controller) and controller.my_pickup_function.picked_up_object!=null:
			return true
	return false

func pointer_surface_hit(hand: Node3D) -> Dictionary:
	if not is_modeling(): return {}
	if tool=="use_edge" and _project_hover_hits.has(hand.get_instance_id()):
		var edge: Dictionary=_project_hover_hits[hand.get_instance_id()]
		var s: Dictionary=document.sketch(active_sketch)
		if not s.is_empty() and edge.has("cursor"):
			var plane:=Document.unpack_transform(s.plane)
			return {"point":document.view_transform*(plane*Vector3(edge.cursor.x,edge.cursor.y,0)*0.001),"project_edge":true}
	var from: Vector3=hand.global_position
	var direction: Vector3=-hand.global_basis.z.normalized()
	var closest:=INF
	var result: Dictionary={}
	# Broad-phase avoids triangle scanning when the ray misses every solid.
	var query:=PhysicsRayQueryParameters3D.create(from,from+direction*10*XRServer.world_scale,4|65536)
	var broad: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if not broad.is_empty():
		result=_face_hit(from,direction)
		if not result.is_empty(): closest=from.distance_to(result.point)
	if plane_display.visible:
		for plane_node in plane_display.get_children():
			if not plane_node.get_meta("sketch_plane",false): continue
			var logical_world: Transform3D=plane_display.global_transform*plane_node.logical_pose
			var inverse: Transform3D=logical_world.affine_inverse()
			var p: Vector3=inverse*from
			var d: Vector3=inverse.basis*direction
			if absf(d.z)<0.00001: continue
			var t: float=-p.z/d.z
			var at:=p+d*t
			var extent: float=plane_node.get_meta("plane_extent")
			if t<=0 or absf(at.x)>extent or absf(at.y)>extent: continue
			var world: Vector3=logical_world*at
			var distance: float=from.distance_to(world)
			if distance<closest:
				closest=distance
				result={"point":world,"plane":true}
	if result.get("plane",false) and tool in ["line","circle","rectangle"]:
		var current: Dictionary=document.sketch(active_sketch)
		var point:=_plane_point(hand)
		if not current.is_empty() and not current.closed and not point.is_empty():
			var inferred:=_infer_point(active_sketch,point.point,_snap_tolerance())
			var snapped: Vector2=inferred.point
			result.point=document.view_transform*(Document.unpack_transform(current.plane)*Vector3(snapped.x,snapped.y,0)*0.001)
	if tool=="select":
		var dimension: Dictionary=sketch_visual.hit_dimension(hand)
		if not dimension.is_empty(): result={"point":dimension.node.global_position,"dimension_label":true}
	if extrude_arrow.label_hit(hand): result={"point":extrude_arrow.label.global_position,"depth_label":true}
	elif extrude_arrow.hit(hand): result={"point":extrude_arrow.tip_point,"arrow":true}
	return result

func _snap_tolerance() -> float:
	return maxf(0.5,30.0*XRServer.world_scale/document.view_transform.basis.x.length())

func begin_sketch():
	if document.busy: return
	active_sketch=-1
	tool="plane_select"
	_chain_ended=false
	message="Select Front, Top or Right in space or in the panel."
	_changed()

func start_angle():
	var s: Dictionary=document.sketch(active_sketch)
	if s.is_empty() or s.kind!="line" or s.points.size()<3: return
	angle_lines.clear();angle_pending={};angle_sketch=active_sketch;tool="angle"
	message="Select two connected lines, then place the angle arc. B cancels."
	_changed()

func angle_line_at(at: Vector2) -> int:
	var s: Dictionary=document.sketch(active_sketch)
	if s.is_empty() or s.kind!="line": return -1
	var count: int=s.points.size() if s.closed and not s.get("closed_by_projection",false) else s.points.size()-1
	var best:=-1
	var distance:=minf(_snap_tolerance(),12.0)
	for i in maxi(0,count):
		var a:=Vector2(s.points[i][0],s.points[i][1]);var b:=Vector2(s.points[(i+1)%s.points.size()][0],s.points[(i+1)%s.points.size()][1])
		var d:=at.distance_to(Geometry2D.get_closest_point_to_segment(at,a,b))
		if d<distance: distance=d;best=i
	return best

func angle_click(at: Vector2):
	var s: Dictionary=document.sketch(active_sketch)
	if not angle_pending.is_empty():
		var placed:=preload("res://cad/CADAngleDimension.gd").placed(s,angle_pending,at)
		var index: int=document.add_angle(active_sketch,placed)
		if index>=0:
			tool="select";angle_pending={};angle_lines.clear()
			message="Angle placed. Select its degree label to edit."
			_changed()
		return
	var index:=angle_line_at(at)
	if index<0: angle_lines.clear();message="Selection cleared. Select the first line."
	elif angle_lines.is_empty(): angle_lines.append(index);message="Select the second line sharing an endpoint."
	else:
		var pair:=preload("res://cad/CADAngleDimension.gd").pair(s,int(angle_lines[0]),index)
		if pair.is_empty(): message="Choose a different line sharing an endpoint; parallel lines have no editable angle."
		else:
			angle_lines.append(index);angle_pending=pair
			message="Place the arc inside the angle, or outside for the supplementary angle."
	_refresh_ui()

func end_sketch_tool():
	if dimension_drag.hand:
		dimension_drag.end(true)
		return
	if ui.confirmation.visible:
		ui.cancel_confirmation()
		return
	if ui.keypad.visible:
		ui.keypad.visible=false
		return
	if tool in ["line","circle","rectangle","plane_select","use_edge","extend_vertex","angle"]:
		angle_lines.clear();angle_pending={}
		var projected: bool=tool=="use_edge"
		_chain_ended=not projected
		tool="select"
		_preview={}
		marker.visible=false
		message="Project finished. Choose Line to draw with these edges, or Extrude a closed profile." if projected else "Chain ended. Select a dimension, choose another tool, or Extrude a closed profile."
		_changed()

func pick_base_plane(hand: Node3D) -> String:
	var result:=""
	var closest:=INF
	var alignment:=0.0
	for name_ in ["Front","Top","Right"]:
		if not plane_visibility.get(name_,true): continue
		var model: Transform3D=document.base_plane(name_)
		model.origin*=0.001
		var world: Transform3D=document.view_transform*model
		var inverse:=world.affine_inverse()
		var p: Vector3=inverse*hand.global_position
		var direction: Vector3=inverse.basis*(-hand.global_basis.z.normalized())
		if absf(direction.z)<0.00001: continue
		var t: float=-p.z/direction.z
		var at:=p+direction*t
		var facing: float=absf(world.basis.z.normalized().dot(-hand.global_basis.z.normalized()))
		if t>0 and absf(at.x)<=0.10 and absf(at.y)<=0.10 and (t<closest-0.001 or (absf(t-closest)<0.001 and facing>alignment)):
			closest=t; alignment=facing; result=name_
	return result

func _line_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color=color
	m.no_depth_test=true
	return m

func _zoom():
	var free := left.my_pickup_function.picked_up_object==null and right.my_pickup_function.picked_up_object==null
	var grips := left.get_float("grip")>0.7 and right.get_float("grip")>0.7
	if not free or not grips:
		_zooming=false
		return
	if tool=="capture_plane": return
	var distance := left.global_position.distance_to(right.global_position)/XRServer.world_scale
	if distance<0.08: return
	if not _zooming:
		_zooming=true
		_table_zoom_start=table_view_scale
		_zoom_distance=distance
		_zoom_scale=XRServer.world_scale
		_zoom_pivot=document.origin_mm*0.001
		_zoom_origin=origin.global_position
	if reference_locked():
		table_view_scale=clampf(_table_zoom_start*distance/_zoom_distance,0.02,50.0)
		_update_reference_view()
		_refresh_ui()
		return
	var new_scale := clampf(_zoom_scale*_zoom_distance/distance,0.02,20.0)
	XRServer.world_scale=new_scale
	origin.global_position=_zoom_pivot+(_zoom_origin-_zoom_pivot)*(new_scale/_zoom_scale)
	_refresh_ui()

func reset_view():
	if reference_locked():
		table_view_scale=1.0
		_update_reference_view()
		_zooming=false
		message="Physical size 1:1. Compare against your real reference block."
		_refresh_ui()
		return
	var old_scale := XRServer.world_scale
	var pivot := camera.global_position if camera else Vector3.ZERO
	XRServer.world_scale=1.0
	if origin: origin.global_position=pivot+(origin.global_position-pivot)/old_scale
	_zooming=false
	_refresh_ui()
	await get_tree().process_frame

func export_selected():
	var b: Dictionary = document.body(selected_body)
	if b.is_empty(): message="Select a CAD body to export."; _refresh_ui(); return
	var result: Dictionary=preload("res://STLExport.gd").save(Document.mesh_from_faces(document.print_export_faces(selected_body)),"ABCCAD_mm_")
	message=preload("res://STLExport.gd").message(result,true)
	if result.error==OK: print("CAD STL path: ",result.path)
	SignalBus.export_finished.emit(result.error==OK,message)
	_refresh_ui()

func new_base_sketch(plane_name: String):
	active_sketch=document.new_sketch(document.base_plane(plane_name))
	plane_visibility["Sketch plane"]=true
	selected_body=-1
	tool="line"
	_chain_ended=false
	message=plane_name+" sketch · click start, then each endpoint. B ends the chain."
	_changed()

func _redraw_planes():
	if not plane_display: return
	for child in plane_display.get_children():
		plane_display.remove_child(child)
		child.queue_free()
	plane_display.transform=document.view_transform
	plane_display.visible=is_modeling()
	var active: Dictionary=document.sketch(active_sketch)
	var names: Array=["Front","Top","Right"] if active.is_empty() else ["Sketch"]
	for name_ in names:
		if not plane_visibility.get("Sketch plane" if name_=="Sketch" else name_,true): continue
		var plane: Transform3D=document.base_plane(name_) if name_!="Sketch" else Document.unpack_transform(active.plane)
		var extent:=100.0
		if name_=="Sketch":
			for member in document.sketch_members(active_sketch):
				for point in Document.profile(member): extent=maxf(extent,maxf(absf(point.x),absf(point.y))+25)
		plane.origin*=0.001
		var quad:=preload("res://cad/CADPlaneVisual.gd").new()
		quad.camera=camera
		var mesh:=QuadMesh.new(); mesh.size=Vector2.ONE*extent*0.002
		quad.mesh=mesh
		quad.set_meta("sketch_plane",true)
		quad.set_meta("plane_extent",extent*0.001)
		quad.transform=plane
		quad.logical_pose=plane
		var m:=StandardMaterial3D.new()
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode=BaseMaterial3D.CULL_DISABLED
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color=Color(0.95,0.97,0.99,0.50 if name_=="Sketch" else 0.12)
		quad.material_override=m
		plane_display.add_child(quad)
		quad.update_depth_bias()
		var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
		var e:=extent*0.001
		for v in [Vector3(-e,-e,0),Vector3(e,-e,0),Vector3(e,-e,0),Vector3(e,e,0),Vector3(e,e,0),Vector3(-e,e,0),Vector3(-e,e,0),Vector3(-e,-e,0),Vector3(-e,0,0),Vector3(e,0,0),Vector3(0,-e,0),Vector3(0,e,0)]: surface.add_vertex(plane*v)
		for i in 32:
			for angle in [TAU*i/32,TAU*(i+1)/32]: surface.add_vertex(plane*Vector3(cos(angle)*0.002,sin(angle)*0.002,0.0004))
		var instance:=MeshInstance3D.new(); instance.mesh=surface.commit()
		instance.material_override=_line_material(Color("7fa4c6"))
		instance.material_override.no_depth_test=true
		plane_display.add_child(instance)
		var label:=Label3D.new()
		label.text=name_ if name_!="Sketch" else "Sketch %d" % document.sketch_root(active_sketch)
		label.font_size=40; label.pixel_size=0.00023
		label.modulate=Color("346896"); label.outline_size=0
		var label_point:=Vector3(-e*0.75,e+0.015,0)
		if name_=="Right": label_point=Vector3(e*0.65,-e-0.015,0)
		elif name_=="Top": label_point=Vector3(e+0.025,-e*0.65,0)
		label.position=plane*label_point
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		plane_display.add_child(label)

func _settings_path() -> String:
	var isolated:=OS.get_environment("ABCCAD_TEST_SAVE_DIR")
	if not isolated.is_empty():
		DirAccess.make_dir_recursive_absolute(isolated)
		return isolated.path_join("advanced_cad.cfg")
	return SETTINGS

func _conversion_history(before: Dictionary, after: Dictionary):
	var old_ids: Array=before.bodies.map(func(b): return int(b.id))
	var new_ids: Array=after.bodies.map(func(b): return int(b.id))
	for b in before.bodies:
		if int(b.id) in new_ids or not b.has("converted_source") or int(b.id) in after.get("deleted_conversions",[]): continue
		var source: Dictionary=b.converted_source
		var t: Transform3D=Document.unpack_transform(source.transform)
		left.restore_block_from_history({"grid_pos":Vector3i(source.grid[0],source.grid[1],source.grid[2]),"shape_type":source.shape,"rotation":t.basis,"color":Color.html(source.color),"world_origin":t.origin})
	for b in after.bodies:
		if int(b.id) in old_ids or not b.has("converted_source"): continue
		var source: Dictionary=b.converted_source
		var t: Transform3D=Document.unpack_transform(source.transform)
		for pos in VoxelDatabase.get_all_voxels():
			var block:=VoxelDatabase.get_voxel(pos)
			if is_instance_valid(block) and block.get_meta("shape_type","")==source.shape and block.global_position.is_equal_approx(t.origin):
				VoxelDatabase.remove_voxel(pos,true,true)
				break

func _place_panel():
	if _panel_placed:
		_update_panel_pose()
		return
	var forward := -camera.global_basis.z
	forward.y=0
	if forward.length()<0.01: forward=Vector3.FORWARD
	forward=forward.normalized()
	var side:=forward.cross(Vector3.UP).normalized()
	panel.global_position=camera.global_position+(forward*1.15-side*0.53+Vector3.DOWN*0.1)*XRServer.world_scale
	panel.look_at(panel.global_position+forward,Vector3.UP)
	panel.scale=Vector3.ONE*XRServer.world_scale*panel_handles.size_factor
	_remember_panel_pose()

func _remember_panel_pose():
	_panel_stage_pose=world_to_stage(panel.global_transform)
	_panel_stage_pose.basis=_panel_stage_pose.basis.orthonormalized()
	_panel_placed=true

func _update_panel_pose():
	if not _panel_placed or not panel.visible: return
	var pose:=stage_to_world(_panel_stage_pose)
	pose.basis=pose.basis.orthonormalized().scaled(Vector3.ONE*XRServer.world_scale*panel_handles.size_factor)
	panel.global_transform=pose

func _can_apply_history(before: Dictionary, after: Dictionary) -> bool:
	var old_ids: Array=before.bodies.map(func(b): return int(b.id))
	var new_ids: Array=after.bodies.map(func(b): return int(b.id))
	for b in before.bodies:
		if int(b.id) in new_ids or not b.has("converted_source"): continue
		for cell in b.converted_source.get("cells",[b.converted_source.grid]):
			if VoxelDatabase.has_voxel(Vector3i(cell[0],cell[1],cell[2])): return false
	for b in after.bodies:
		if int(b.id) in old_ids or not b.has("converted_source"): continue
		var source: Dictionary=b.converted_source
		var t: Transform3D=Document.unpack_transform(source.transform)
		for cell in source.get("cells",[source.grid]):
			var block:=VoxelDatabase.get_voxel(Vector3i(cell[0],cell[1],cell[2]))
			if is_instance_valid(block) and (block.get_meta("shape_type","")!=source.shape or not block.global_position.is_equal_approx(t.origin)): return false
	return true

func _infer_point(id: int, point: Vector2, tolerance: float) -> Dictionary:
	if not auto_constraints: return {"point":point,"constraint":{},"label":"Auto constraints off"}
	return document.infer_point(id,point,tolerance)

func reference_locked() -> bool:
	return not document.reference_plane.is_empty() and document.reference_plane.get("locked",false)

func stage_to_world(pose: Transform3D) -> Transform3D:
	return origin.global_transform*XRServer.get_reference_frame()*Transform3D(pose.basis,pose.origin*XRServer.world_scale)

func world_to_stage(pose: Transform3D) -> Transform3D:
	var local: Transform3D=(origin.global_transform*XRServer.get_reference_frame()).affine_inverse()*pose
	return Transform3D(local.basis,local.origin/XRServer.world_scale)

func probe_point(hand: Node3D) -> Vector3:
	return hand.global_transform*(probe_offset_mm*0.001*XRServer.world_scale)

func start_table_capture():
	if document.busy: return
	# Restore tracking meters before collecting physical contacts.
	if reference_locked():
		table_view_scale=1.0
		_update_reference_view()
	else: await reset_view()
	contact_points.clear()
	tool="capture_plane"
	message="Contact 1/3: touch the blue probe to the surface, then trigger."
	_redraw_reference()
	_refresh_ui()

func capture_contact(hand: Node3D):
	if document.busy or tool!="capture_plane": return
	var point:=world_to_stage(Transform3D(Basis.IDENTITY,probe_point(hand))).origin
	if not contact_points.is_empty() and contact_points[-1].distance_to(point)<0.02:
		message="Move the probe at least 20 mm to another spot."
		_refresh_ui()
		return
	contact_points.append(point)
	if contact_points.size()==3:
		var result: Dictionary=preload("res://cad/CADReferencePlane.gd").from_contacts(contact_points)
		if result.has("error"):
			contact_points.pop_back()
			message=result.error
		else:
			var pose: Transform3D=result.pose
			var world:=stage_to_world(pose)
			world.origin*=1000.0
			document.set_reference_plane({"plane_mm":Document.pack_transform(world),"stage_pose":Document.pack_transform(pose),"locked":true,"lock_rotation":false})
			tool="select"
			message="Table plane locked. Choose Sketch on table; 1:1 matches physical millimeters."
	else: message="Contact %d/3: touch another spot; make a wide triangle." % (contact_points.size()+1)
	_redraw_reference()
	_refresh_ui()

func cancel_table_capture():
	contact_points.clear()
	tool="select"
	message="Table capture cancelled. Previous plane retained."
	_redraw_reference()
	_refresh_ui()

func new_table_sketch():
	if document.busy or document.reference_plane.is_empty(): return
	active_sketch=document.new_sketch(Document.unpack_transform(document.reference_plane.plane_mm))
	plane_visibility["Sketch plane"]=true
	selected_body=-1
	tool="line"
	_chain_ended=false
	message="Table sketch · click start, then each endpoint. B ends the chain."
	_changed()

func toggle_plane_lock():
	if document.busy or document.reference_plane.is_empty(): return
	var ref: Dictionary=document.reference_plane.duplicate(true)
	ref.locked=not ref.locked
	table_view_scale=1.0
	document.set_reference_plane(ref)
	message="Plane locked in tracking space." if ref.locked else "Plane unlocked; ordinary view zoom is active."
	_refresh_ui()

func toggle_part_rotation_lock():
	if document.busy or document.reference_plane.is_empty(): return
	var ref: Dictionary=document.reference_plane.duplicate(true)
	ref.lock_rotation=not ref.get("lock_rotation",false)
	document.set_reference_plane(ref)

func _update_reference_view():
	if not document: return
	var ref: Dictionary=document.reference_plane
	var signature:=str([ref.get("plane_mm",[]),ref.get("stage_pose",[]),ref.get("locked",false)])
	if signature!=_reference_signature:
		_reference_signature=signature
		table_view_scale=1.0
	var view:=Transform3D.IDENTITY
	if reference_locked():
		var model:=Document.unpack_transform(ref.plane_mm)
		model.origin*=0.001
		var world:=stage_to_world(Document.unpack_transform(ref.stage_pose))
		view=preload("res://cad/CADReferencePlane.gd").anchored_view(model,world,table_view_scale*XRServer.world_scale)
	if not document.view_transform.is_equal_approx(view):
		document.set_view_transform(view)
		if draw_node: draw_node.transform=view
		if plane_display: plane_display.transform=view
	if reference_display and reference_locked():
		reference_display.transform=stage_to_world(Document.unpack_transform(ref.stage_pose))
		reference_display.basis=reference_display.basis.scaled(Vector3.ONE*XRServer.world_scale)

func _redraw_reference():
	if not reference_display: return
	for child in reference_display.get_children():
		reference_display.remove_child(child)
		child.queue_free()
	reference_display.transform=Transform3D.IDENTITY
	var ref: Dictionary=document.reference_plane
	if not ref.is_empty():
		var pose:=stage_to_world(Document.unpack_transform(ref.stage_pose)) if ref.locked else Document.unpack_transform(ref.plane_mm)
		if not ref.locked: pose.origin*=0.001
		reference_display.transform=pose
		if ref.locked: reference_display.basis=reference_display.basis.scaled(Vector3.ONE*XRServer.world_scale)
		var grid:=SurfaceTool.new()
		grid.begin(Mesh.PRIMITIVE_LINES)
		for i in range(-250,251,25):
			for v in [Vector3(i,-250,0),Vector3(i,250,0),Vector3(-250,i,0),Vector3(250,i,0)]: grid.add_vertex(v*0.001)
		var instance:=MeshInstance3D.new()
		instance.mesh=grid.commit()
		var material:=_line_material(Color("4e9eff"))
		material.no_depth_test=false
		instance.material_override=material
		reference_display.add_child(instance)
		var label:=Label3D.new()
		label.text="TABLE · LOCKED" if ref.locked else "TABLE"
		label.position=Vector3(0,0.28,0)
		label.font_size=36
		label.pixel_size=0.0003
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		reference_display.add_child(label)
	for point in contact_points:
		var sphere:=MeshInstance3D.new()
		sphere.mesh=probe_marker.mesh
		sphere.material_override=probe_marker.material_override
		reference_display.add_child(sphere)
		sphere.global_position=stage_to_world(Transform3D(Basis.IDENTITY,point)).origin
	reference_display.visible=is_modeling() and plane_visibility.get("Table",true)

func display_scale() -> float:
	return table_view_scale if reference_locked() else 1.0/XRServer.world_scale

func set_print_preview(value: bool):
	print_enabled=value
	_print_request+=1
	print_preview.cancel()
	print_loading=false
	_print_revision=""
	if not value:
		print_display.visible=false
		_set_source_visible(true)
	else: _update_print_preview()
	_refresh_ui()

func _set_source_visible(value: bool):
	for child in document.get_children():
		if child.has_meta("cad_body_id"):
			var mesh=child.get_node("MeshInstance3D")
			mesh.visible=value or int(child.body_id)!=selected_body

func _update_print_preview():
	if not print_enabled: return
	# A moving part stays in its ordinary exact view; regenerate once released.
	if document.busy:
		print_preview.cancel()
		_print_request+=1
		_print_revision=""
		print_loading=false
		print_display.visible=false
		_set_source_visible(true)
		return
	var body: Dictionary=document.body(selected_body)
	if body.is_empty():
		print_preview.cancel()
		_print_request+=1
		_print_revision=""
		print_loading=false
		print_display.visible=false
		print_display.mesh=null
		_set_source_visible(true)
		_refresh_ui()
		return
	var revision:=str([body,document.reference_plane.get("plane_mm",[])])
	if revision==_print_revision:
		_set_source_visible(not print_display.visible)
		return
	_print_revision=revision
	_print_request+=1
	var request:=_print_request
	print_preview.cancel()
	print_loading=true
	print_progress=0
	print_display.visible=false
	_set_source_visible(true)
	_refresh_ui()
	var plane: Transform3D=Document.unpack_transform(document.reference_plane.plane_mm) if not document.reference_plane.is_empty() else Transform3D.IDENTITY
	var mesh: ArrayMesh=await print_preview.build(body.faces.duplicate(true),plane)
	if request!=_print_request or not print_enabled: return
	print_loading=false
	if mesh:
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color.html(body.get("color","70cbbfff"))
		material.vertex_color_use_as_albedo=true
		material.cull_mode=BaseMaterial3D.CULL_BACK
		material.roughness=0.65
		print_display.mesh=mesh
		print_display.material_override=material
		print_display.transform=document.view_transform
		print_display.visible=true
		_set_source_visible(false)
		message="Print preview · 0.2 mm layers · no supports. Export remains the exact CAD solid."
	else:
		print_display.visible=false
		_set_source_visible(true)
		message=print_preview.error if not print_preview.error.is_empty() else "Preview cancelled."
	_refresh_ui()

func set_probe_offset(value: Vector3):
	probe_offset_mm=value
	var cfg:=ConfigFile.new()
	cfg.load(_settings_path())
	cfg.set_value("cad","probe_offset_mm",value)
	cfg.save(_settings_path())

func open_load_menu():
	SignalBus.request_toggle_menu.emit()
	var menu=get_parent().get_node("Viewport2Din3D/Viewport").get_child(0)
	menu._show_load_menu()

## Each context has a fixed, compact layout. Stable command IDs decouple actions
## from wedge positions so different contexts can use four, six, or eight slots.
func _wheel_item(id: String, label_: String, icon: String, hint: String, available: bool=true, active: bool=false) -> Dictionary:
	return {"id":id,"label":label_,"icon":icon,"hint":hint,"enabled":available,"active":active}

func wheel_context() -> Dictionary:
	var sketch: Dictionary=document.sketch(active_sketch)
	var has_sketch:=not sketch.is_empty()
	var can_undo: bool=not document.undo_steps.is_empty()
	var can_redo: bool=not document.redo_steps.is_empty()
	if ui.mode=="sketch" and has_sketch:
		return {"id":"sketch","title":"SKETCH","items":[
			_wheel_item("line","Line","line","Click points to draw",true,tool=="line"),
			_wheel_item("circle","Center\ncircle","circle","Center, then radius",true,tool=="circle"),
			_wheel_item("rectangle","Center\nrectangle","rectangle","Center, then corner",true,tool=="rectangle"),
			_wheel_item("use_edge","Use edge","use_edge","Project a face edge",true,tool=="use_edge"),
			_wheel_item("extrude","Extrude","extrude","Choose enclosed areas" if not regions().is_empty() else "Close an area first",not regions().is_empty()),
			_wheel_item("finish_tool","Finish\ntool","finish","End the current tool",tool!="select"),
			_wheel_item("dimension","Dimension","dimension","Point at a size to edit" if not sketch_visual.dimensions.is_empty() else "Draw a shape first",not sketch_visual.dimensions.is_empty()),
			_wheel_item("select","Select","select","Select geometry",true,tool=="select")
		]}
	if ui.mode=="extrude" and has_sketch:
		var has_target: bool=not document.body(selected_body).is_empty()
		return {"id":"extrude","title":"EXTRUDE","items":[
			_wheel_item("apply_extrude","Apply","finish","Commit this extrusion",not selected_regions.is_empty() and (operation=="New" or has_target)),
			_wheel_item("reverse","Reverse","reverse","Flip extrusion direction",not selected_regions.is_empty()),
			_wheel_item("operation_new","New\nbody","extrude","Create a separate part",true,operation=="New"),
			_wheel_item("edit_sketch","Edit\nsketch","sketch","Return to sketch tools"),
			_wheel_item("operation_remove","Remove","remove","Cut from selected part",has_target,operation=="Remove"),
			_wheel_item("operation_add","Add","add","Join to selected part",has_target,operation=="Add")
		]}
	if ui.mode=="sketch" and not has_sketch:
		return {"id":"plane","title":"SKETCH PLANE","items":[
			_wheel_item("plane_front","Front","plane","Sketch on Front"),
			_wheel_item("plane_right","Right","plane","Sketch on Right"),
			_wheel_item("plane_top","Top","plane","Sketch on Top"),
			_wheel_item("cancel_plane","Cancel","back","Return to part studio")
		]}
	if ui.mode=="select" and not selected_hit.is_empty():
		return {"id":"face","title":"SELECTED FACE","items":[
			_wheel_item("sketch_face","Sketch\non face","sketch","Draw on this face"),
			_wheel_item("project_face","Project\nface","use_edge","Create sketch from edges"),
			_wheel_item("select","Select","select","Select another face"),
			_wheel_item("undo","Undo","undo","Undo the last edit",can_undo)
		]}
	return {"id":"studio","title":"PART STUDIO","items":[
		_wheel_item("sketch","New\nsketch","sketch","Choose a sketch plane"),
		_wheel_item("select","Select","select","Select a face or dimension"),
		_wheel_item("undo","Undo","undo","Undo the last edit",can_undo),
		_wheel_item("redo","Redo","redo","Redo the last edit",can_redo)
	]}

func run_wheel_command(command: String):
	if not is_modeling() or document.busy or ui.confirmation.visible or ui.keypad.visible: return
	# Revalidate the displayed command against the live context before acting.
	var available:=false
	for item in wheel_context().items:
		if item.id==command and item.enabled: available=true;break
	if not available: return
	match command:
		"sketch": begin_sketch(); ui.show_command("sketch")
		"sketch_face": new_sketch(true); ui.show_command("sketch")
		"project_face": convert_edges(); ui.show_command("sketch")
		"plane_front", "plane_top", "plane_right": new_base_sketch(command.trim_prefix("plane_").capitalize())
		"cancel_plane": ui.show_command("select")
		"line", "circle", "rectangle":
			ui.show_command("sketch")
			choose_tool(command)
		"use_edge": start_use_edge()
		"extrude": ui.show_command("extrude")
		"edit_sketch": ui.show_command("sketch")
		"dimension":
			choose_tool("select")
			message="Dimension · point at a dimension label and pull trigger to edit it."
		"select":
			if ui.mode=="sketch": choose_tool("select")
			else: ui.show_command("select")
		"finish_tool": end_sketch_tool()
		"reverse": reverse_extrude_direction()
		"operation_new", "operation_add", "operation_remove": operation=command.trim_prefix("operation_").capitalize()
		"apply_extrude":
			if await extrude(): ui.show_command("select")
		"undo": document.undo()
		"redo": document.redo()
	_refresh_ui()

func _update_region_hover():
	var next := ""
	if ui.mode=="extrude" and right.get_is_active() and not _ray_hits_panel(right):
		var hit:=_plane_point(right,false)
		if not hit.is_empty():
			for region in regions():
				if preload("res://cad/CADSketchRegions.gd").contains(region,hit.point):
					next=str(region.id)
					break
	if next!=hovered_region:
		hovered_region=next
		sketch_visual.redraw()
