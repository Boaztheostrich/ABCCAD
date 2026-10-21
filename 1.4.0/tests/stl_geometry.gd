extends Node3D
var failures := 0
var checks := 0
var cases := []
func key(v: Vector3) -> String:
	return "%.5f,%.5f,%.5f" % [v.x, v.y, v.z]
func triangles(points: PackedVector3Array) -> Dictionary:
	var result := {}
	for i in range(0, points.size(), 3):
		var triangle := [key(points[i]), key(points[i + 1]), key(points[i + 2])]
		triangle.sort()
		var triangle_key := str(triangle)
		result[triangle_key] = result.get(triangle_key, 0) + 1
	return result
func bounds(points: PackedVector3Array) -> AABB:
	var result := AABB(points[0], Vector3.ZERO)
	for v in points: result = result.expand(v)
	return result
func record(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("STL FAIL: " + label)
func properties(bytes: PackedByteArray) -> Dictionary:
	var edges: Dictionary={}
	var normals_ok:=true
	var volume:=0.0
	var origin:=Vector3(bytes.decode_float(96),bytes.decode_float(100),bytes.decode_float(104))
	for i in bytes.decode_u32(80):
		var base:=84+i*50
		var normal:=Vector3(bytes.decode_float(base),bytes.decode_float(base+4),bytes.decode_float(base+8))
		var points: Array=[]
		for j in 3:
			var at:=base+12+j*12
			points.append(Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8)))
		var geometric: Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
		normals_ok=normals_ok and normal.dot(geometric)>0.999
		volume+=(points[0]-origin).dot((points[1]-origin).cross(points[2]-origin))/6
		for j in 3:
			var a:=key(points[j]);var b:=key(points[(j+1)%3])
			var edge:=a+"/"+b if a<b else b+"/"+a
			if not edges.has(edge): edges[edge]=[0,0]
			edges[edge][0]+=1;edges[edge][1]+=1 if a<b else -1
	var closed:=true
	for edge in edges.values(): closed=closed and edge[0]==2 and edge[1]==0
	return {"normals":normals_ok,"volume":volume,"closed":closed}

func _ready():
	var exporter = load("res://VoxelExporter.gd").new()
	add_child(exporter)
	var scenes = ["cube", "brick", "wedge", "m_cube", "Corner_piece"]
	var rotations: Array[Basis] = []
	for forward in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		for up in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
			if absf(forward.dot(up)) > 0.9: continue
			var right = up.cross(forward).normalized()
			rotations.append(Basis(right, up, forward))
	var out_dir := OS.get_environment("ABCCAD_STL_TEST_DIR")
	if out_dir.is_empty(): out_dir = "/private/tmp/abccad-stl-geometry"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for scene_name in scenes:
		for index in rotations.size():
			var block = load("res://" + scene_name + ".tscn").instantiate()
			block.top_level = true
			add_child(block)
			block.freeze = true
			block.set_meta("shape_type", "corner_wedge" if scene_name == "Corner_piece" else scene_name)
			block.global_transform = Transform3D(rotations[index], Vector3(-1.3, 2.1, 0.7))
			block.get_node("VoxelLogic")._on_dropped(block)
			var expected := PackedVector3Array()
			var mesh_node = block.get_node("MeshInstance3D")
			for vertex in mesh_node.mesh.get_faces(): expected.append(mesh_node.global_transform * vertex)
			var file_path = out_dir.path_join(scene_name + "_" + str(index) + ".stl")
			var mesh: ArrayMesh = exporter.build_export_mesh()
			var result = STLIO.Exporter.SaveToPath(mesh, file_path)
			record(result == OK, scene_name + " writes STL")
			var bytes := FileAccess.get_file_as_bytes(file_path)
			var actual := PackedVector3Array()
			var count := bytes.decode_u32(80)
			record(bytes.size() == 84 + int(count) * 50 and count > 0, scene_name + " parses")
			for i in count:
				for j in 3:
					var off = 84 + i * 50 + 12 + j * 12
					actual.append(Vector3(bytes.decode_float(off), bytes.decode_float(off + 4), bytes.decode_float(off + 8)))
			var solid:=properties(bytes)
			record(solid.normals,scene_name+" stored normals agree with STL right-hand winding")
			record(solid.volume>0,scene_name+" outward winding gives positive solid volume")
			record(solid.closed,scene_name+" every surface edge has two opposite-oriented uses")
			var expected_bounds := bounds(expected)
			var actual_bounds := bounds(actual)
			var aligned = actual_bounds.position.is_equal_approx(expected_bounds.position) and actual_bounds.size.is_equal_approx(expected_bounds.size)
			record(aligned, scene_name + " rotation " + str(index) + " world bounds match rendered mesh")
			var expected_vertices := {}
			var actual_vertices := {}
			for v in expected: expected_vertices[key(v)] = true
			for v in actual: actual_vertices[key(v)] = true
			record(expected_vertices == actual_vertices, scene_name + " rotation " + str(index) + " vertices match rendered mesh")
			record(triangles(expected) == triangles(actual), scene_name + " rotation " + str(index) + " every triangle matches rendered mesh exactly once")
			cases.append({"shape":scene_name,"rotation":index,"aligned":aligned,"expected_min":str(expected_bounds.position),"actual_min":str(actual_bounds.position),"expected_size":str(expected_bounds.size),"actual_size":str(actual_bounds.size)})
			VoxelDatabase.voxel_grid.clear()
			VoxelDatabase.undo_stack.clear()
			VoxelDatabase.redo_stack.clear()
			block.queue_free()
			await get_tree().process_frame
	# A combined assembly must preserve relative alignment, without exporting
	# multi-cell blocks once per occupied cell or including an unplaced block.
	var assembly_expected := PackedVector3Array()
	for i in 7:
		var scene_name: String = scenes[i % scenes.size()]
		var block = load("res://" + scene_name + ".tscn").instantiate()
		block.top_level = true
		add_child(block)
		block.freeze = true
		block.set_meta("shape_type", "corner_wedge" if scene_name == "Corner_piece" else scene_name)
		var position := Vector3(i * 1.5, 1.3, -2.0)
		# Last cube and brick touch the first cube/brick assembly at known grid cells.
		if i == 5: position = Vector3(0.1, 1.3, -2.0)
		if i == 6: position = Vector3(0.25, 1.3, -2.0)
		block.global_transform = Transform3D(rotations[(i * 5) % rotations.size()], position)
		block.get_node("VoxelLogic")._on_dropped(block)
		if block.is_queued_for_deletion(): continue
		var node = block.get_node("MeshInstance3D")
		for v in node.mesh.get_faces(): assembly_expected.append(node.global_transform * v)
	var unplaced = load("res://cube.tscn").instantiate()
	add_child(unplaced)
	unplaced.freeze = true
	unplaced.position = Vector3(20, 20, 20)
	var assembly_mesh: ArrayMesh = exporter.build_export_mesh()
	var assembly_path := out_dir.path_join("mixed_assembly.stl")
	record(STLIO.Exporter.SaveToPath(assembly_mesh, assembly_path) == OK, "mixed assembly writes STL")
	var assembly_bytes := FileAccess.get_file_as_bytes(assembly_path)
	var assembly_actual := PackedVector3Array()
	for i in assembly_bytes.decode_u32(80):
		for j in 3:
			var off = 84 + i * 50 + 12 + j * 12
			assembly_actual.append(Vector3(assembly_bytes.decode_float(off), assembly_bytes.decode_float(off + 4), assembly_bytes.decode_float(off + 8)))
	record(triangles(assembly_actual) == triangles(assembly_expected), "mixed/adjacent blocks line up with rendered geometry; unplaced block excluded")
	var report := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(cases,"  "))
	report.close()
	print("STL GEOMETRY RESULT: %d checks, %d failures, %d shape/rotation cases" % [checks,failures,cases.size()])
	get_tree().quit(0 if failures == 0 else 1)
