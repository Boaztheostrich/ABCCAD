extends Node3D

var failures: Array[String] = []
var checks: int = 0
var left: XRController3D
var right: XRController3D
var save_system: Node
var save_result: bool
var load_result: bool
var left_tracker: XRPositionalTracker
var right_tracker: XRPositionalTracker

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func frames(count: int = 3):
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func tracker_for(tracker_name: String, position: Vector3) -> XRPositionalTracker:
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = tracker_name
	tracker.set_pose("default", Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("grip", 0.0)
	tracker.set_input("primary", Vector2.ZERO)
	tracker.set_input("ax_button", false)
	tracker.set_input("by_button", false)
	tracker.set_input("trigger_click", false)
	tracker.set_input("menu_button", false)
	XRServer.add_tracker(tracker)
	return tracker

func press(tracker: XRPositionalTracker, action: String):
	tracker.set_input(action, true)
	await frames(2)
	tracker.set_input(action, false)
	await frames(2)

func spawn(controller: XRController3D, tracker: XRPositionalTracker, index: int) -> Node3D:
	controller.current_block_index = index
	var before := get_tree().get_nodes_in_group("abccad_blocks")
	await press(tracker, "ax_button")
	for block in get_tree().get_nodes_in_group("abccad_blocks"):
		if block not in before: return block
	return null

func clear_build():
	save_system._clear_world()
	await frames()
	VoxelDatabase.undo_stack.clear()
	VoxelDatabase.redo_stack.clear()

func _ready():
	left_tracker = tracker_for("left_hand", Vector3(-0.3, 1.4, -0.5))
	right_tracker = tracker_for("right_hand", Vector3(0.3, 1.4, -0.5))
	var player := preload("res://player.tscn").instantiate()
	add_child(player)
	left = player.get_node("LeftHand")
	right = player.get_node("RightHand")
	left.debug_logging = false
	right.debug_logging = false
	save_system = preload("res://SaveSystem.gd").new()
	save_system.save_directory = "/private/tmp/abccad-regression-" + str(OS.get_process_id())
	add_child(save_system)
	SignalBus.save_finished.connect(func(success, _message): save_result = success)
	SignalBus.load_finished.connect(func(success, _message): load_result = success)
	await frames()
	check(left.get_is_active() and right.get_is_active(), "both tracked controllers active")
	# Every shape from either hand must retain its type through placement and redo.
	for controller in [left, right]:
		var tracker := left_tracker if controller == left else right_tracker
		for index in controller.block_scenes.size():
			var block := await spawn(controller, tracker, index)
			var expected := BlockInteractions.shape_for_scene(controller.block_scenes[index])
			check(block != null, controller.name + " spawns " + expected)
			if block == null: continue
			check(block.get_meta("shape_type") == expected, "correct shape metadata " + controller.name + " " + expected)
			controller.my_pickup_function._pick_up_object(block)
			controller.my_pickup_function.drop_object()
			await frames()
			check(VoxelDatabase.get_voxel_count() > 0, "placed cells " + expected)
			var placed_cells := VoxelDatabase.get_voxel_count()
			controller.my_pickup_function._pick_up_object(block)
			check(VoxelDatabase.get_voxel_count() == 0, "rapid re-grab clears footprint " + controller.name + " " + expected)
			controller.my_pickup_function.drop_object()
			await frames()
			check(VoxelDatabase.get_voxel_count() == placed_cells, "rapid re-release preserves footprint " + controller.name + " " + expected)
			VoxelDatabase.perform_undo(left)
			await frames()
			check(VoxelDatabase.get_voxel_count() == 0, "undo clears " + expected)
			VoxelDatabase.perform_redo(left)
			await frames()
			var restored := get_tree().get_nodes_in_group("abccad_blocks")
			check(restored.size() == 1 and restored[0].get_meta("shape_type") == expected, "redo preserves " + controller.name + " " + expected)
			var expected_cells := VoxelDatabase.get_voxel_count()
			await get_tree().create_timer(0.55).timeout
			controller.my_pickup_function._pick_up_object(restored[0])
			check(VoxelDatabase.get_voxel_count() == 0, "grabbing redone block clears old footprint " + controller.name + " " + expected)
			restored[0].global_position = Vector3(2, 1.5, -2)
			controller.my_pickup_function.drop_object()
			await frames()
			check(VoxelDatabase.get_voxel_count() == expected_cells, "moving redone block leaves no phantom cells " + controller.name + " " + expected)
			SignalBus.request_save_game.emit("redo-moved")
			SignalBus.request_load_game.emit("redo-moved.json")
			await frames()
			check(load_result, "moved redone block remains loadable " + controller.name + " " + expected)
			await clear_build()
	# Transfer before first placement: exercise the real XR Tools pickup methods.
	for source in [left, right]:
		var source_tracker := left_tracker if source == left else right_tracker
		var destination := right if source == left else left
		var destination_tracker := right_tracker if source == left else left_tracker
		var block := await spawn(source, source_tracker, 1)
		destination.my_pickup_function._pick_up_object(block)
		check(destination.held_cube == block, "other hand tracks fresh block from " + source.name)
		await press(destination_tracker, "by_button")
		check(block.get_node("MeshInstance3D").get_color() == destination.current_color, "other hand recolors fresh block from " + source.name)
		destination.my_pickup_function.drop_object()
		check(destination.held_cube == null, "release clears hand state " + destination.name)
		# Placement must not add duplicate controller signal connections per voxel.
		BlockInteractions.connect_block(block)
		BlockInteractions.connect_block(block)
		var controller_connections := 0
		for connection in block.get_signal_connection_list("grabbed"):
			if connection.callable.get_object() in [left, right]: controller_connections += 1
		check(controller_connections == 2, "one callback per controller")
		await clear_build()
	# A hand-to-hand swap is not a placement, even above an occupied cell.
	for source in [left, right]:
		var source_tracker := left_tracker if source == left else right_tracker
		var destination := right if source == left else left
		for index in source.block_scenes.size():
			var obstacle := await spawn(source, source_tracker, 1)
			obstacle.global_position = Vector3(0, 1.5, 0)
			obstacle.get_node("VoxelLogic")._on_dropped(obstacle)
			var block := await spawn(source, source_tracker, index)
			source.my_pickup_function._pick_up_object(block)
			block.global_position = obstacle.global_position
			var history_size := VoxelDatabase.undo_stack.size()
			destination.my_pickup_function._pick_up_object(block)
			await frames()
			var survived := is_instance_valid(block) and not block.is_queued_for_deletion()
			var label: String = source.name + " " + str(index)
			check(survived, "handoff above occupied cell preserves block " + label)
			check(destination.my_pickup_function.grab_collision_mask & block.picked_up_layer != 0 if survived else false, "other hand can detect held layer " + label)
			check(VoxelDatabase.undo_stack.size() == history_size, "handoff does not create placement history " + label)
			check(VoxelDatabase.get_voxel_count() == 1 and VoxelDatabase.get_voxel(Vector3i(0,15,0)) == obstacle, "handoff preserves neighbour cells " + label)
			if survived:
				check(destination.held_cube == block and source.held_cube == null and source.my_pickup_function.picked_up_object == null, "handoff tracks only destination hand " + label)
				block.global_position = Vector3(3, 1.5, -3)
				destination.my_pickup_function.drop_object()
				await frames()
				SignalBus.request_save_game.emit("handoff")
				SignalBus.request_load_game.emit("handoff.json")
				await frames()
				check(load_result and get_tree().get_nodes_in_group("abccad_blocks").size() == 2, "handoff build saves and restores both blocks " + label)
			await clear_build()
	# Drive grip input through active XR trackers and real proximity detection.
	for source in [left, right]:
		var source_tracker := left_tracker if source == left else right_tracker
		var destination := right if source == left else left
		var destination_tracker := right_tracker if source == left else left_tracker
		var block := await spawn(source, source_tracker, 1)
		destination_tracker.set_pose("default", Transform3D(Basis.IDENTITY, block.global_position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await frames(5)
		destination_tracker.set_input("grip", 1.0)
		await frames(5)
		check(destination.my_pickup_function.picked_up_object == block and destination.held_cube == block, "tracked grip grabs opposite-hand block " + destination.name)
		destination_tracker.set_input("grip", 0.0)
		await frames(3)
		check(destination.held_cube == null, "tracked grip release clears " + destination.name)
		destination_tracker.set_pose("default", Transform3D(Basis.IDENTITY, Vector3(0.3 if destination == right else -0.3, 1.4, -0.5)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await clear_build()
	# World-space blocks must not inherit player locomotion or recenter transforms.
	for controller in [left, right]:
		var tracker := left_tracker if controller == left else right_tracker
		player.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(2, 0, 3))
		await frames()
		var expected_spawn: Vector3 = controller.global_position + Vector3.UP * 0.1
		var moved_block := await spawn(controller, tracker, 1)
		moved_block.freeze = true
		check(moved_block.global_basis.is_equal_approx(controller.global_basis), "spawn preserves world rotation after player movement " + controller.name)
		check(moved_block.global_position.distance_to(expected_spawn) < 0.08, "spawn uses world coordinates after player movement " + controller.name)
		var placed_position := Vector3(0.8, 1.1, -0.8)
		moved_block.global_position = placed_position
		moved_block.get_node("VoxelLogic")._on_dropped(moved_block)
		placed_position = moved_block.global_position
		var placed_basis: Basis = moved_block.global_basis
		player.basis = Basis(Vector3.UP, -PI / 2.0)
		player.position += Vector3(3, 0, -2)
		await frames()
		check(moved_block.global_basis.is_equal_approx(placed_basis), "placed block keeps world rotation when player turns " + controller.name)
		check(moved_block.global_position.is_equal_approx(placed_position), "placed block stays in world when player moves " + controller.name)
		SignalBus.request_save_game.emit("moved-origin")
		SignalBus.request_load_game.emit("moved-origin.json")
		await frames()
		var loaded_blocks := get_tree().get_nodes_in_group("abccad_blocks")
		check(load_result and loaded_blocks.size() == 1 and loaded_blocks[0].global_position.is_equal_approx(placed_position), "restore preserves saved world position after movement " + controller.name)
		check(loaded_blocks[0].global_basis.is_equal_approx(placed_basis), "restore preserves saved world rotation " + controller.name)
		var restored_position: Vector3 = loaded_blocks[0].global_position
		player.basis = Basis.IDENTITY
		player.position += Vector3(-1, 0, 4)
		await frames()
		check(loaded_blocks[0].global_basis.is_equal_approx(placed_basis), "loaded block keeps rotation when player turns " + controller.name)
		check(loaded_blocks[0].global_position.is_equal_approx(restored_position), "loaded block stays in world when player moves " + controller.name)
		player.transform = Transform3D.IDENTITY
		await clear_build()
	# UI trigger clicks must not also run the left-hand standalone export shortcut.
	var export_requests: Array = []
	SignalBus.request_export_stl.connect(func(): export_requests.append(true))
	var left_pointer = left.get_node("LeftHand/FunctionPointer")
	left_pointer.enabled = true
	left.export_cooldown = 0
	left._on_trigger_pressed()
	check(export_requests.is_empty(), "left UI trigger does not also export")
	left_pointer.enabled = false
	left._on_trigger_pressed()
	check(export_requests.size() == 1, "left standalone trigger requests shared exporter")
	# Adjacent and negative-coordinate multi-cell blocks (all within one metre).
	for index in [0, 0, 3]:
		var block := await spawn(left, left_tracker, index)
		block.global_position = Vector3(-0.25 if index == 3 else 0.1 + 0.3 * VoxelDatabase.get_voxel_count(), 1.0, -0.3 if index == 3 else 0.0)
		block.get_node("VoxelLogic")._on_dropped(block)
	var original_cells := VoxelDatabase.get_voxel_count()
	var original_objects := get_tree().get_nodes_in_group("abccad_blocks").size()
	SignalBus.request_save_game.emit("roundtrip")
	check(save_result, "save succeeds")
	SignalBus.request_load_game.emit("roundtrip.json")
	await frames()
	check(load_result, "load succeeds")
	check(VoxelDatabase.get_voxel_count() == original_cells, "all cells survive loading")
	check(get_tree().get_nodes_in_group("abccad_blocks").size() == original_objects, "all physical blocks survive loading")
	var ownership: Dictionary = {}
	for pos in VoxelDatabase.get_all_voxels():
		var obj := VoxelDatabase.get_voxel(pos)
		ownership[obj] = ownership.get(obj, 0) + 1
	check(ownership.size() == original_objects, "adjacent blocks retain separate cell ownership")
	for obj in ownership:
		check(obj.get_node("VoxelLogic").last_grid_positions.size() == ownership[obj], "loaded footprint matches cell ownership")
	# Legacy saves use exact origins, without new object IDs.
	var path: String = save_system.save_directory.path_join("roundtrip.json")
	var legacy = JSON.parse_string(FileAccess.get_file_as_string(path))
	for item in legacy: item.erase("object_id")
	var legacy_file := FileAccess.open(save_system.save_directory.path_join("legacy.json"), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	SignalBus.request_load_game.emit("legacy.json")
	await frames()
	check(load_result and VoxelDatabase.get_voxel_count() == original_cells, "legacy saves load all cells")
	ownership.clear()
	for pos in VoxelDatabase.get_all_voxels(): ownership[VoxelDatabase.get_voxel(pos)] = true
	check(ownership.size() == original_objects, "legacy adjacent blocks retain ownership")
	# Remove one loaded block; all cells of the others must survive.
	var victim = ownership.keys()[0]
	var removed_count: int = victim.get_node("VoxelLogic").last_grid_positions.size()
	VoxelDatabase.remove_voxel(victim.get_node("VoxelLogic").last_grid_positions[0], true, true)
	await frames()
	check(VoxelDatabase.get_voxel_count() == original_cells - removed_count, "removing one loaded block preserves neighbours")
	# Malformed saves cannot erase an existing build.
	var corrupt := FileAccess.open(save_system.save_directory.path_join("corrupt.json"), FileAccess.WRITE)
	corrupt.store_string('[{"x": 1}]')
	corrupt.close()
	var before_count := VoxelDatabase.get_voxel_count()
	SignalBus.request_load_game.emit("corrupt.json")
	check(not load_result and VoxelDatabase.get_voxel_count() == before_count, "invalid save leaves build intact")
	# Load also removes freshly spawned blocks absent from the grid.
	var unplaced := await spawn(right, right_tracker, 1)
	right.my_pickup_function._pick_up_object(unplaced)
	SignalBus.request_load_game.emit("roundtrip.json")
	await frames()
	check(not is_instance_valid(unplaced) and right.held_cube == null, "loading clears unplaced held blocks")
	# Replacing a build while both hands hold each type must leave no deferred
	# drop placements or stale pickup references, including on repeated loads.
	for index in left.block_scenes.size():
		var held_left := await spawn(left, left_tracker, index)
		var held_right := await spawn(right, right_tracker, index)
		left.my_pickup_function._pick_up_object(held_left)
		right.my_pickup_function._pick_up_object(held_right)
		SignalBus.request_load_game.emit("roundtrip.json")
		await frames()
		check(load_result and not is_instance_valid(held_left) and not is_instance_valid(held_right), "load replaces both held blocks type " + str(index))
		check(left.my_pickup_function.picked_up_object == null and right.my_pickup_function.picked_up_object == null and left.held_cube == null and right.held_cube == null, "load clears both pickup states type " + str(index))
		check(VoxelDatabase.get_voxel_count() == original_cells, "deferred drops cannot add cells after load type " + str(index))
		SignalBus.request_save_game.emit("repeated")
		SignalBus.request_load_game.emit("repeated.json")
		await frames()
		check(load_result and VoxelDatabase.get_voxel_count() == original_cells and get_tree().get_nodes_in_group("abccad_blocks").size() == original_objects, "repeated save/load preserves build type " + str(index))
	# UI has a single action owner and loads only close on success.
	var menu := preload("res://Menu_screen_0.tscn").instantiate()
	add_child(menu)
	await frames()
	var save_requests: Array = []
	SignalBus.request_save_game.connect(func(filename): save_requests.append(filename))
	menu.btn_save.pressed.emit()
	check(save_requests.size() == 1, "save button dispatches exactly once")
	menu.btn_to_load_screen.pressed.emit()
	check(menu.find_child("LoadMenu", true, false).visible, "load button opens file list")
	menu.selected_file_name = "missing.json"
	menu.visible = true
	menu._on_load_confirm_pressed()
	check(menu.visible and not menu.btn_load_confirm.disabled, "failed load keeps menu open and allows retry")
	menu.queue_free()
	await clear_build()
	XRServer.remove_tracker(left_tracker)
	XRServer.remove_tracker(right_tracker)
	print("REGRESSION RESULT: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
