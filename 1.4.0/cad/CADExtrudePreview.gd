extends Node3D
## Disposable geometry only: never changes the document, history, or export.
const Doc=preload("res://cad/CADDocument.gd")
const MAX_BOOLEAN_TRIANGLES=4096
var workbench: Node3D
var tool_mesh: MeshInstance3D
var result_mesh: MeshInstance3D
var _hidden_mesh: MeshInstance3D
var _signature:=""
var _generation:=0
var _settled:=0.0
var _building:=false
var _done:=false
var last_build_ms:=0.0
var _boolean_slow:=false
func _ready():
	tool_mesh=MeshInstance3D.new(); add_child(tool_mesh)
	result_mesh=MeshInstance3D.new(); add_child(result_mesh)
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=Color(1,0.65,0.12,0.32)
	tool_mesh.material_override=material
	workbench.document.changed.connect(invalidate)
func _restore():
	if is_instance_valid(_hidden_mesh): _hidden_mesh.visible=true
	_hidden_mesh=null
	if workbench.face_highlight:
		workbench.face_highlight.visible=workbench.is_modeling() and not workbench.selected_hit.is_empty()
func invalidate():
	_generation+=1; _signature=""; _done=false
	_restore()
	if result_mesh: result_mesh.visible=false
func cancel():
	invalidate()
	if tool_mesh: tool_mesh.visible=false
func refresh(delta: float):
	var s: Dictionary=workbench.selected_profile()
	if not workbench.extrude_arrow.visible or s.is_empty() or absf(workbench.depth_mm)<0.01:
		if not _signature.is_empty() or tool_mesh.visible or result_mesh.visible: cancel()
		return
	var target: Dictionary=workbench.document.body(workbench.selected_body if workbench.selected_body>=0 else int(s.body_id))
	var signature:=str([workbench._profile_signature,workbench.depth_mm,workbench.operation,workbench.selected_body])
	if signature!=_signature:
		invalidate(); _signature=signature; _settled=0
		tool_mesh.mesh=prism(s,workbench.depth_mm)
		tool_mesh.visible=tool_mesh.mesh!=null
		tool_mesh.material_override.albedo_color=Color(1,0.24,0.12,0.36) if workbench.operation=="Remove" else Color(1,0.65,0.12,0.32)
	transform=workbench.document.view_transform
	tool_mesh.transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.001),Vector3.ZERO)
	result_mesh.transform=tool_mesh.transform
	_settled+=delta
	if workbench.operation=="New" or target.is_empty() or _boolean_slow or target.faces.size()/3>MAX_BOOLEAN_TRIANGLES: return
	if _settled>=0.12 and not _building and not _done:
		_done=true
		_build(s.duplicate(true),target.duplicate(true),workbench.depth_mm,workbench.operation,_generation)
static func prism(s: Dictionary,depth: float) -> ArrayMesh:
	if s.has("region_profiles"):
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pose:=Doc.unpack_transform(s.plane)
		for region in preload("res://cad/CADSketchRegions.gd").unpacked(s.region_profiles):
			var caps:=preload("res://cad/CADSketchRegions.gd").triangles(region)
			for z in [0.0,depth]:
				for p in caps:surface.add_vertex(pose*Vector3(p.x,p.y,z))
			for poly in [region.outer]+region.holes:
				for i in poly.size():
					var a: Vector2=poly[i];var b: Vector2=poly[(i+1)%poly.size()]
					for v in [Vector3(a.x,a.y,0),Vector3(b.x,b.y,0),Vector3(b.x,b.y,depth),Vector3(a.x,a.y,0),Vector3(b.x,b.y,depth),Vector3(a.x,a.y,depth)]:surface.add_vertex(pose*v)
		surface.generate_normals();return surface.commit()
	var polygon:=Doc.profile(s)
	var indices:=Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return null
	var pose:=Doc.unpack_transform(s.plane)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [0.0,depth]:
		for i in indices:
			var p: Vector2=polygon[i]
			surface.add_vertex(pose*Vector3(p.x,p.y,z))
	for i in polygon.size():
		var a:=polygon[i]; var b:=polygon[(i+1)%polygon.size()]
		for v in [Vector3(a.x,a.y,0),Vector3(b.x,b.y,0),Vector3(b.x,b.y,depth),Vector3(a.x,a.y,0),Vector3(b.x,b.y,depth),Vector3(a.x,a.y,depth)]: surface.add_vertex(pose*v)
	surface.generate_normals()
	return surface.commit()
func _build(s: Dictionary,target: Dictionary,depth: float,operation: String,generation: int):
	if operation=="Remove" and workbench.document.removal_overlap_depth(s,target,depth)<=0.002: return
	_building=true
	var started:=Time.get_ticks_usec()
	var root:=CSGMesh3D.new(); root.mesh=Doc.mesh_from_faces(target.faces)
	var cutter: CSGShape3D=Doc.extrusion_tool(s,depth,operation,target)
	cutter.operation=CSGShape3D.OPERATION_SUBTRACTION if operation=="Remove" else CSGShape3D.OPERATION_UNION
	root.add_child(cutter); root.visible=false; add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame
	var mesh:=root.bake_static_mesh()
	root.queue_free(); _building=false
	last_build_ms=(Time.get_ticks_usec()-started)/1000.0
	# Includes two renderer frames: stop rebuilding if preview work is costly.
	if last_build_ms>100: _boolean_slow=true
	if generation!=_generation or not workbench.extrude_arrow.visible or mesh==null: return
	var faces:=Doc.faces_from_mesh(mesh)
	if faces.is_empty() or (operation=="Remove" and Doc.volume(faces)>=Doc.volume(target.faces)): return
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color.html(target.get("color","70cbbfff"))
	material.roughness=0.38
	result_mesh.mesh=mesh; result_mesh.material_override=material; result_mesh.visible=true
	for child in workbench.document.get_children():
		if child.get_meta("cad_body_id",-1)==int(target.id):
			_hidden_mesh=child.get_node("MeshInstance3D"); _hidden_mesh.visible=false
			if not workbench.selected_hit.is_empty() and int(workbench.selected_hit.source.id)==int(target.id): workbench.face_highlight.visible=false
	tool_mesh.visible=false
