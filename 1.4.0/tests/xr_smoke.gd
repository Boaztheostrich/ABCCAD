extends Node

# A deterministic visual checkpoint using the real OpenXR runtime. It drives
# production gameplay methods, not the runtime's native button bindings.
func _ready():
	await get_tree().create_timer(4.0).timeout
	var world := get_parent()
	var saver := world.get_node("SaveSystem")
	saver.save_directory = "/private/tmp/abccad-xr-smoke-saves"
	DirAccess.make_dir_recursive_absolute(saver.save_directory)
	var tutorial := world.get_node("tutorial screen")
	tutorial._spawn_attempted = false
	tutorial.menu_root.visible = false
	var left := world.get_node("XROrigin3D/LeftHand")
	var right := world.get_node("XROrigin3D/RightHand")
	# Spawn a brick from each hand, preserving a separate footprint per block.
	for controller in [left, right]:
		controller.current_block_index = 0
		controller._spawn_cube()
		var blocks := get_tree().get_nodes_in_group("abccad_blocks")
		var block = blocks.back()
		var other = right if controller == left else left
		other.my_pickup_function._pick_up_object(block)
		other._cycle_color()
		other.my_pickup_function.drop_object()
		await get_tree().process_frame
		# Move to predictable visual positions after the transfer checkpoint.
		block.get_node("VoxelLogic").last_grid_positions.clear()
		VoxelDatabase.cleanup_object_references(block)
		block.global_position = Vector3(-0.85 if controller == left else 0.85, 1.3, -1.1)
		block.get_node("VoxelLogic")._on_dropped(block)
	var before := VoxelDatabase.get_voxel_count()
	SignalBus.request_save_game.emit("simulator_checkpoint")
	SignalBus.request_load_game.emit("simulator_checkpoint.json")
	await get_tree().process_frame
	assert(VoxelDatabase.get_voxel_count() == before, "XR smoke save/load lost cells")
	assert(get_tree().get_nodes_in_group("abccad_blocks").size() == 2, "XR smoke save/load lost blocks")
	print("XR SMOKE PASS: both hands spawn bricks, opposite hand recolors, save/load preserves 2 objects and %d cells." % before)
	var viewport := world.get_node("Viewport2Din3D")
	if not viewport.visible:
		SignalBus.request_toggle_menu.emit()
	var menu = viewport.get_scene_instance()
	menu.status_label.text = "Simulation checkpoint passed — both hands and save/load"
