extends MeshInstance3D
var document: Node3D
var body_id := -1
func set_color(color: Color):
	material_override.albedo_color=color
	var body: Dictionary=document.body(body_id)
	if not body.is_empty(): body.color=color.to_html()
	document.changed.emit()
func get_color() -> Color:
	return material_override.albedo_color
