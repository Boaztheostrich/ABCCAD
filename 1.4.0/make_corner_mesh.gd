@tool
extends EditorScript

func _run() -> void:
	var mesh := _create_corner_wedge_mesh()
	var err := ResourceSaver.save(mesh, "res://WITHUV_corner_wedge_mesh.tres")
	if err == OK:
		print("✅ Corner wedge mesh saved to res://WITHUV_corner_wedge_mesh.tres")
	else:
		print("❌ Failed to save mesh, error code:", err)


func _create_corner_wedge_mesh() -> ArrayMesh:
	var s := 0.05  # Half of voxel size

	# 6 vertices of the triangular prism
	var BL_bot := Vector3(-s, -s, -s)  # Back-left bottom
	var BR_bot := Vector3(+s, -s, -s)  # Back-right bottom
	var FL_bot := Vector3(-s, -s, +s)  # Front-left bottom

	var BL_top := Vector3(-s, +s, -s)  # Back-left top
	var BR_top := Vector3(+s, +s, -s)  # Back-right top
	var FL_top := Vector3(-s, +s, +s)  # Front-left top

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	var add_tri = func(
		v1: Vector3,
		v2: Vector3,
		v3: Vector3,
		normal: Vector3,
		uv1: Vector2,
		uv2: Vector2,
		uv3: Vector2
	) -> void:
		vertices.append_array([v1, v2, v3])
		normals.append_array([normal, normal, normal])
		uvs.append_array([uv1, uv2, uv3])

	# --- Bottom face (triangle) ---
	# Map to full 0..1 area
	add_tri.call(
		BL_bot,
		FL_bot,
		BR_bot,
		Vector3(0, -1, 0),
		Vector2(0, 0),
		Vector2(0, 1),
		Vector2(1, 0)
	)

	# --- Top face (triangle) ---
	add_tri.call(
		BL_top,
		BR_top,
		FL_top,
		Vector3(0, +1, 0),
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1)
	)

	# --- Back face (rectangle) ---
	# Quad: BL_bot (0,0), BR_bot (1,0), BR_top (1,1), BL_top (0,1)
	add_tri.call(
		BL_bot,
		BR_bot,
		BR_top,
		Vector3(0, 0, -1),
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1)
	)
	add_tri.call(
		BL_bot,
		BR_top,
		BL_top,
		Vector3(0, 0, -1),
		Vector2(0, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	)

	# --- Left face (rectangle) ---
	# Quad: FL_bot (1,0), BL_bot (0,0), BL_top (0,1), FL_top (1,1)
	add_tri.call(
		FL_bot,
		BL_bot,
		BL_top,
		Vector3(-1, 0, 0),
		Vector2(1, 0),
		Vector2(0, 0),
		Vector2(0, 1)
	)
	add_tri.call(
		FL_bot,
		BL_top,
		FL_top,
		Vector3(-1, 0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1)
	)

	# --- Diagonal face (rectangle) ---
	# Quad: BR_bot (0,0), FL_bot (1,0), FL_top (1,1), BR_top (0,1)
	var diag_normal := Vector3(1, 0, 1).normalized()
	add_tri.call(
		BR_bot,
		FL_bot,
		FL_top,
		diag_normal,
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1)
	)
	add_tri.call(
		BR_bot,
		FL_top,
		BR_top,
		diag_normal,
		Vector2(0, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs  # <<– important

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return arr_mesh
