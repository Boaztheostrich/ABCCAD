extends MeshInstance3D

func _ready():
	# Get the material from the mesh if no override exists
	if material_override == null:
		var mesh_material = mesh.surface_get_material(0)
		if mesh_material:
			material_override = mesh_material.duplicate()
	else:
		material_override = material_override.duplicate()
	
	print("[CUBE MESH] Material ready, type:", material_override.get_class())
	print("[CUBE MESH] Current color:", get_color())

func set_color(new_color: Color):
	print("[CUBE MESH] set_color called with:", new_color)
	
	if material_override == null:
		print("[CUBE MESH] ERROR: No material_override!")
		return
	
	# Check if it's a ShaderMaterial (your new outline shader)
	if material_override is ShaderMaterial:
		material_override.set_shader_parameter("replace_color", new_color)
		print("[CUBE MESH] Shader color applied successfully!")
	# Fallback for StandardMaterial3D (if you're still testing)
	elif material_override is StandardMaterial3D:
		material_override.albedo_color = new_color
		print("[CUBE MESH] Standard material color applied!")
	else:
		print("[CUBE MESH] ERROR: Unknown material type:", material_override.get_class())

func get_color() -> Color:
	if material_override == null:
		return Color.WHITE
	
	# Check material type and get color accordingly
	if material_override is ShaderMaterial:
		var color = material_override.get_shader_parameter("replace_color")
		return color if color != null else Color.WHITE
	elif material_override is StandardMaterial3D:
		return material_override.albedo_color
	
	return Color.WHITE
