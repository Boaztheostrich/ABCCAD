@tool
extends EditorScript

func _run():
	var mesh = _create_corner_wedge_mesh()
	var err = ResourceSaver.save(mesh, "res://corner_wedge_mesh_new.tres")
	if err == OK:
		print("✅ Corner wedge mesh saved to res://corner_wedge_mesh_again.tres")
	else:
		print("❌ Failed to save mesh, error code:", err)

func _create_corner_wedge_mesh() -> ArrayMesh:
	var s = 0.05  # Half of voxel size
	
	# 6 vertices of the triangular prism
	var BL_bot = Vector3(-s, -s, -s)  # Back-left bottom
	var BR_bot = Vector3(+s, -s, -s)  # Back-right bottom
	var FL_bot = Vector3(-s, -s, +s)  # Front-left bottom
	
	var BL_top = Vector3(-s, +s, -s)  # Back-left top
	var BR_top = Vector3(+s, +s, -s)  # Back-right top
	var FL_top = Vector3(-s, +s, +s)  # Front-left top
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	
	var add_tri = func(v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3):
		vertices.append_array([v1, v2, v3])
		normals.append_array([normal, normal, normal])
	
	# Bottom face (triangle)
	add_tri.call(BL_bot, FL_bot, BR_bot, Vector3(0, -1, 0))
	
	# Top face (triangle)
	add_tri.call(BL_top, BR_top, FL_top, Vector3(0, +1, 0))
	
	# Back face (rectangle)
	add_tri.call(BL_bot, BR_bot, BR_top, Vector3(0, 0, -1))
	add_tri.call(BL_bot, BR_top, BL_top, Vector3(0, 0, -1))
	
	# Left face (rectangle)
	add_tri.call(FL_bot, BL_bot, BL_top, Vector3(-1, 0, 0))
	add_tri.call(FL_bot, BL_top, FL_top, Vector3(-1, 0, 0))
	
	# Diagonal face (rectangle)
	var diag_normal = Vector3(1, 0, 1).normalized()
	add_tri.call(BR_bot, FL_bot, FL_top, diag_normal)
	add_tri.call(BR_bot, FL_top, BR_top, diag_normal)
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return arr_mesh
