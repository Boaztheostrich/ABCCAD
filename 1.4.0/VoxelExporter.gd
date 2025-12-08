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

func _export_voxels_to_stl():
	var voxel_count = VoxelDatabase.get_voxel_count()
	
	if voxel_count == 0:
		print("❌ No voxels to export! Place some cubes first.")
		return
	
	print("📦 Exporting", voxel_count, "voxels...")
	
	# Create surface tool for combining
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Get all voxel grid positions
	var grid_positions = VoxelDatabase.get_all_voxels()
	
	var cube_count = 0
	var wedge_count = 0
	var corner_wedge_count = 0
	
	# Handle different shape types
	for grid_pos in grid_positions:
		var world_pos = VoxelDatabase.grid_to_world(grid_pos)
		var voxel_data = VoxelDatabase.get_voxel_data(grid_pos)
		
		if voxel_data and is_instance_valid(voxel_data.object):
			# print("  🔧 Exporting", voxel_data.shape_type, "at grid:", grid_pos, "world:", world_pos)
			
			match voxel_data.shape_type:
				"cube":
					_add_cube_to_surface(st, world_pos, VoxelDatabase.voxel_size)
					cube_count += 1
				"corner_wedge":
					_add_corner_wedge_to_surface(st, world_pos, VoxelDatabase.voxel_size, voxel_data.rotation)
					corner_wedge_count += 1
				"wedge":
					_add_wedge_to_surface(st, world_pos, VoxelDatabase.voxel_size, voxel_data.rotation)
					wedge_count += 1
				_:
					print("⚠️ Unknown shape type:", voxel_data.shape_type, "at", grid_pos)
	
	print("📊 Export summary: ", cube_count, "cubes, ", wedge_count, "wedges", corner_wedge_count, "corner wedges")
	
	# Commit the combined mesh
	var combined_mesh := st.commit()
	print("✅ Mesh combined with", combined_mesh.get_surface_count(), "surface(s)")
	
	# Get the Downloads folder path (cross-platform)
	var downloads_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	
	# Create timestamped filename
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var filename = "voxel_build_" + timestamp + ".stl"
	var file_path: String = downloads_path.path_join(filename)
	
	var result = STLIO.Exporter.SaveToPath(combined_mesh, file_path)
	
	if result == OK:
		print("✅✅✅ STL EXPORTED SUCCESSFULLY! ✅✅✅")
		print("📂 Saved to Downloads folder: ", file_path)
	else:
		print("❌ Export failed with error:", result)

# --- GEOMETRY HELPERS ---

func _add_cube_to_surface(st: SurfaceTool, pos: Vector3, size: float):
	var verts = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)
	]
	for i in range(verts.size()):
		verts[i] = verts[i] * size + pos
	var faces = [
		[0, 2, 1,  0, 3, 2], [5, 7, 4,  5, 6, 7], [4, 3, 0,  4, 7, 3],
		[1, 6, 5,  1, 2, 6], [3, 6, 2,  3, 7, 6], [4, 1, 5,  4, 0, 1]
	]
	for face in faces:
		for idx in face:
			st.add_vertex(verts[idx])

func _add_corner_wedge_to_surface(st: SurfaceTool, pos: Vector3, size: float, rotation: Basis):
	var half_size = size * 0.5
	var center = pos + Vector3(half_size, half_size, half_size)
	var peak = Vector3(-0.5, 0.5, -0.5)
	var bot_back_left = Vector3(-0.5, -0.5, -0.5)
	var bot_back_right = Vector3(0.5, -0.5, -0.5)
	var bot_fwd_right = Vector3(0.5, -0.5, 0.5)
	var bot_fwd_left = Vector3(-0.5, -0.5, 0.5)
	var verts = [peak, bot_back_left, bot_back_right, bot_fwd_right, bot_fwd_left]
	
	var x_tilt = 270.0; var y_spin = 90.0
	var correction_basis = Basis(Vector3.RIGHT, deg_to_rad(x_tilt)) * Basis(Vector3.UP, deg_to_rad(y_spin))
	
	for i in range(verts.size()):
		verts[i] = (rotation * (correction_basis * verts[i])) * size + center
	
	var triangles = [
		[verts[1], verts[3], verts[2]], [verts[1], verts[4], verts[3]],
		[verts[1], verts[0], verts[2]], [verts[1], verts[4], verts[0]],
		[verts[0], verts[2], verts[3]], [verts[0], verts[3], verts[4]]
	]
	for tri in triangles:
		for vert in tri: st.add_vertex(vert)

func _add_wedge_to_surface(st: SurfaceTool, pos: Vector3, size: float, rotation: Basis):
	var half_size = size * 0.5
	var center = pos + Vector3(half_size, half_size, half_size)
	var verts = [
		Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
	]
	for i in range(verts.size()):
		verts[i] = (rotation * (verts[i] * size)) + center
	var triangles = [
		[0, 2, 1], [0, 3, 2], [3, 5, 2], [3, 4, 5],
		[3, 4, 0], [2, 5, 1], [0, 4, 5], [0, 5, 1],
	]
	for tri in triangles:
		for idx in tri: st.add_vertex(verts[idx])
