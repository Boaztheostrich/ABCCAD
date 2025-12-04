extends MeshInstance3D

func _ready():
	# Get the material from the mesh if no override exists
	if material_override == null:
		var mat = StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = mat
	else:
		material_override = material_override.duplicate()
		if material_override is StandardMaterial3D:
			material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	print("[CORNER WEDGE MESH] Material ready, current color:", get_color())

func set_color(new_color: Color):
	print("[CUBE MESH] set_color called with:", new_color)
	if material_override:
		material_override.albedo_color = new_color
		print("[CUBE MESH] Color applied successfully!")
	else:
		print("[CUBE MESH] ERROR: No material_override!")

func get_color() -> Color:
	if material_override:
		return material_override.albedo_color
	return Color.WHITE
	
