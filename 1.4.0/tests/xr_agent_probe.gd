extends Node
# Optional read-only scene telemetry for native OpenXR validation.
var elapsed := 0.0
var output := ""
var last_save := {}
var last_load := {}
func _ready():
	output = OS.get_environment("ABCCAD_STATE_FILE")
	var test_saves = OS.get_environment("ABCCAD_TEST_SAVE_DIR")
	if not test_saves.is_empty():
		get_parent().get_node("SaveSystem").save_directory = test_saves
		DirAccess.make_dir_recursive_absolute(test_saves)
		var menu = get_parent().get_node("Viewport2Din3D/Viewport").get_child(0)
		menu.save_folder_path = test_saves
	SignalBus.save_finished.connect(func(success, message): last_save = {"success": success, "message": message})
	SignalBus.load_finished.connect(func(success, message): last_load = {"success": success, "message": message})
func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
func _process(delta):
	elapsed += delta
	if elapsed < 0.1 or get_tree().current_scene == null or output.is_empty(): return false
	elapsed = 0.0
	var state := {"ticks": Time.get_ticks_msec(), "hands": {}, "blocks": []}
	for hand in get_tree().get_nodes_in_group("block_controllers"):
		var pickup = hand.my_pickup_function
		var held = pickup.picked_up_object
		state.hands[str(hand.name)] = {"position": vec(hand.global_position), "active": hand.get_is_active(), "spawn": hand.is_button_pressed("ax_button"), "color_button": hand.is_button_pressed("by_button"), "grip": hand.get_float("grip"), "trigger": hand.is_button_pressed("trigger_click"), "stick": [hand.get_vector2("primary").x, hand.get_vector2("primary").y], "color_index": hand.current_color_index, "block_index": hand.current_block_index, "held": held.get_instance_id() if is_instance_valid(held) else 0}
	for block in get_tree().get_nodes_in_group("abccad_blocks"):
		state.blocks.append({"id": block.get_instance_id(), "position": vec(block.global_position), "rotation": [block.global_basis.x.x,block.global_basis.x.y,block.global_basis.x.z,block.global_basis.y.x,block.global_basis.y.y,block.global_basis.y.z,block.global_basis.z.x,block.global_basis.z.y,block.global_basis.z.z], "shape": block.get_meta("shape_type", ""), "held": block.is_picked_up(), "color": block.get_node("MeshInstance3D").get_color().to_html() if block.get_node_or_null("MeshInstance3D") and block.get_node("MeshInstance3D").has_method("get_color") else ""})
	var db = get_tree().root.get_node("VoxelDatabase")
	state.voxels = db.voxel_grid.size()
	state.export_faces = []
	var placed := {}
	for cell in db.voxel_grid:
		var object = db.voxel_grid[cell].object
		if is_instance_valid(object) and not object.is_queued_for_deletion(): placed[object.get_instance_id()] = object
	for object in placed.values():
		var mesh_node = object.get_node_or_null("MeshInstance3D")
		if mesh_node and mesh_node.mesh:
			for vertex in mesh_node.mesh.get_faces(): state.export_faces.append(vec(mesh_node.global_transform * vertex))
	var workbench = get_tree().get_first_node_in_group("cad_workbench")
	if workbench != null:
		state.cad={"enabled":workbench.enabled,"modeling":workbench.is_modeling(),"tool":workbench.tool,"active_sketch":workbench.active_sketch,"selected_body":workbench.selected_body,"depth_mm":workbench.depth_mm,"operation":workbench.operation,"message":workbench.message,"world_scale":XRServer.world_scale,"xr_origin":preload("res://cad/CADDocument.gd").pack_transform(workbench.origin.global_transform),"document":workbench.document.snapshot()}
		state.cad.merge({"display_scale":workbench.display_scale(),"view_transform":preload("res://cad/CADDocument.gd").pack_transform(workbench.document.view_transform),"table_pose":preload("res://cad/CADDocument.gd").pack_transform(workbench.reference_display.global_transform),"contacts":workbench.contact_points.map(func(p):return vec(p)),"probe_offset_mm":vec(workbench.probe_offset_mm),"print_enabled":workbench.print_enabled,"print_loading":workbench.print_loading,"print_progress":workbench.print_progress,"print_vertices":workbench.print_display.mesh.surface_get_array_len(0) if workbench.print_display.mesh else 0})
	state.last_save = last_save
	state.last_load = last_load
	state.head = vec(get_parent().get_node("XROrigin3D/XRCamera3D").global_position)
	state.ui = []
	for node in get_tree().root.find_children("*", "XRToolsViewport2DIn3D", true, false):
		var panel := {"path": str(node.get_path()), "visible": node.visible, "position": vec(node.global_position), "buttons": []}
		for button in node.get_node("Viewport").find_children("*", "Button", true, false):
			var center = button.get_global_rect().get_center()
			var point = Vector3((center.x / node.viewport_size.x - 0.5) * node.screen_size.x, (0.5 - center.y / node.viewport_size.y) * node.screen_size.y, 0)
			panel.buttons.append({"name": str(button.name), "text": button.text, "disabled": button.disabled, "visible": button.is_visible_in_tree(), "position": vec(node.global_transform * point)})
		state.ui.append(panel)
	var file = FileAccess.open(output + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))
		file.close()
		DirAccess.rename_absolute(output + ".tmp", output)
	return false
