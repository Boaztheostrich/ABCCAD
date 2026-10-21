class_name BlockInteractions
extends RefCounted

static func shape_for_scene(scene: PackedScene) -> String:
	var scene_name := scene.resource_path.get_file().get_basename().to_lower()
	if "brick" in scene_name: return "brick"
	if "m_cube" in scene_name: return "m_cube"
	if "corner" in scene_name: return "corner_wedge"
	if "wedge" in scene_name or "triangle" in scene_name: return "wedge"
	return "cube"

static func find_scene(scenes: Array[PackedScene], shape: String) -> PackedScene:
	for scene in scenes:
		if scene != null and shape_for_scene(scene) == shape:
			return scene
	return null

static func connect_block(block: Node) -> void:
	block.add_to_group("abccad_blocks")
	for controller in block.get_tree().get_nodes_in_group("block_controllers"):
		var grabbed_callback := Callable(controller, "on_cube_grabbed")
		var released_callback := Callable(controller, "on_cube_released")
		if block.has_signal("grabbed") and not block.is_connected("grabbed", grabbed_callback):
			block.connect("grabbed", grabbed_callback)
		if block.has_signal("released") and not block.is_connected("released", released_callback):
			block.connect("released", released_callback)

# A swap releases the source grab without calling its pickup's drop_object().
# Reconcile after the swap, so the old hand stops tracking/colliding with it.
static func finish_release(block: Node, pickup: Node3D) -> void:
	if not is_instance_valid(block) or not is_instance_valid(pickup):
		return
	if pickup.picked_up_object == block and block.get_picked_up_by() != pickup:
		pickup.drop_object()
