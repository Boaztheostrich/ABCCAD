extends MeshInstance3D

func _ready():
	# Get the material from the mesh if no override exists
	if material_override == null:
		var mesh_material = mesh.surface_get_material(0)
		if mesh_material:
			material_override = mesh_material.duplicate()
	else:
		material_override = material_override.duplicate()
	
	print("[CUBE MESH] Material ready, current color:", get_color())

func set_color(new_color: Color):
	if material_override == null:
		print("[WEDGE MESH] ERROR: No material_override!")
		return
	if material_override is ShaderMaterial:
		material_override.set_shader_parameter("replace_color", new_color)
		print("[WEDGE MESH] Shader color applied")
	elif material_override is StandardMaterial3D:
		material_override.albedo_color = new_color
		print("[WEDGE MESH] Standard color applied")
	else:
		print("[WEDGE MESH] Unknown material type:", material_override.get_class())

func get_color() -> Color:
	if material_override == null:
		return Color.WHITE
	if material_override is ShaderMaterial:
		var c = material_override.get_shader_parameter("replace_color")
		return c if c != null else Color.WHITE
	elif material_override is StandardMaterial3D:
		return material_override.albedo_color
	return Color.WHITE
