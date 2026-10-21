extends Node

# This script lives in the Main scene and just waits for the signal
# It doesn't care about controllers or buttons.

var export_cooldown: float = 0.0
const EXPORT_COOLDOWN_TIME: float = 1.5

func _ready():
	# This connects the "Wireless Bus" to this script
	SignalBus.request_export_stl.connect(_on_export_requested)

func _process(delta):
	if export_cooldown > 0:
		export_cooldown -= delta

func _on_export_requested():
	if export_cooldown > 0:
		print("⏳ Export on cooldown, wait", snappedf(export_cooldown, 0.1), "seconds...")
		return
	
	print("🎯 Signal Received - VoxelExporter starting export!")
	_export_voxels_to_stl()
	export_cooldown = EXPORT_COOLDOWN_TIME

# The rendered mesh is the geometry source of truth. Grid positions are cell
# centers, not mesh corners, and multi-cell blocks must only be exported once.
func build_export_parts(units_per_meter: float = 1.0) -> Array[Mesh]:
	var cad = get_tree().get_first_node_in_group("cad_document")
	var export_frame: Transform3D=cad.export_frame_mm() if cad != null else Transform3D.IDENTITY
	var has_reference: bool=cad != null and not cad.reference_plane.is_empty()
	var objects: Dictionary = {}
	for grid_pos in VoxelDatabase.get_all_voxels():
		var data = VoxelDatabase.get_voxel_data(grid_pos)
		if data and is_instance_valid(data.object) and not data.object.is_queued_for_deletion():
			objects[data.object.get_instance_id()] = data.object
	var parts: Array[Mesh]=[]
	for block in objects.values():
		var faces: Array=[]
		for child in block.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():continue
			for vertex in mesh_instance.mesh.get_faces():
				var world: Vector3=mesh_instance.global_transform*vertex
				var point: Vector3=(export_frame*(world*1000.0))*(0.001*units_per_meter) if has_reference else world*units_per_meter
				faces.append([point.x,point.y,point.z])
		if not faces.is_empty():parts.append(preload("res://cad/CADDocument.gd").mesh_from_faces(faces))
	if cad != null:
		for body in cad.bodies:
			var faces: Array=[]
			for point in body.faces:
				var transformed: Vector3=(export_frame*Vector3(point[0],point[1],point[2]))*(0.001*units_per_meter)
				faces.append([transformed.x,transformed.y,transformed.z])
			parts.append(preload("res://cad/CADDocument.gd").mesh_from_faces(faces))
	return parts

func build_export_mesh(units_per_meter: float = 1.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0
	for part in build_export_parts(units_per_meter):
		for vertex in part.get_faces():
			surface.add_vertex(vertex)
			vertex_count += 1
	if vertex_count == 0:return null
	return surface.commit()

func build_print_export_mesh(units_per_meter: float=1000.0) -> ArrayMesh:
	var combined_mesh:=build_export_mesh(units_per_meter)
	if combined_mesh==null: return null
	var cad=get_tree().get_first_node_in_group("cad_document")
	# Normalize the complete assembly with one rigid transform and translation;
	# never independently recenter parts and destroy their alignment.
	var frame:=Transform3D.IDENTITY
	if cad!=null and cad.reference_plane.is_empty():
		frame=cad.print_frame_mm()
		frame.origin*=units_per_meter*0.001
	elif cad==null:
		frame=Transform3D(Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN),Vector3.ZERO)
	return preload("res://cad/CADDocument.gd").mesh_from_faces(preload("res://cad/CADDocument.gd").print_ready_faces(preload("res://cad/CADDocument.gd").faces_from_mesh(combined_mesh),frame))

func _export_voxels_to_stl():
	var cad = get_tree().get_first_node_in_group("cad_document")
	var workbench = get_tree().get_first_node_in_group("cad_workbench")
	var millimeters: bool=(workbench != null and workbench.enabled) or (cad != null and (not cad.bodies.is_empty() or not cad.reference_plane.is_empty()))
	# Mesh.get_faces() welds vertices at 0.0001 mesh units. Build in final units
	# so advanced exports retain 0.0001 mm rather than 0.1 mm resolution.
	var combined_mesh := build_print_export_mesh(1000.0 if millimeters else 1.0)
	if combined_mesh == null:
		SignalBus.export_finished.emit(false,"Nothing to export. Place a block or extrude a CAD part first.")
		return
	var result: Dictionary=preload("res://STLExport.gd").save(combined_mesh,"voxel_build_",[],build_export_parts(1000.0 if millimeters else 1.0))
	var message: String=preload("res://STLExport.gd").message(result,millimeters)
	print(message)
	if result.error==OK: print("STL path: ",result.path)
	SignalBus.export_finished.emit(result.error==OK,message)
