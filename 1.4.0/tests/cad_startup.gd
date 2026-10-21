extends Node
const Main=preload("res://main.tscn")
var checks:=0
var failures:=0
var world: Node3D
var left_tracker: XRPositionalTracker
var right_tracker: XRPositionalTracker
var export_requests:=0
func check(ok: bool,label_: String):
	checks+=1
	if ok:print("STARTUP PASS: "+label_)
	else:failures+=1;push_error("STARTUP FAIL: "+label_)
func frames(count: int=3):
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame
func tracker(name_: String,position: Vector3) -> XRPositionalTracker:
	var value:=XRPositionalTracker.new();value.type=XRServer.TRACKER_CONTROLLER;value.name=name_
	value.set_pose("default",Transform3D(Basis.IDENTITY,position),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	value.set_input("primary",Vector2.ZERO)
	for button in ["ax_button","by_button","trigger_click","menu_button"]:value.set_input(button,false)
	XRServer.add_tracker(value);return value
func press(value: XRPositionalTracker,button: String):
	value.set_input(button,true);await frames()
	value.set_input(button,false);await frames()
func restart():
	if is_instance_valid(world):
		world.queue_free();await get_tree().process_frame
		VoxelDatabase.voxel_grid.clear();VoxelDatabase.undo_stack.clear();VoxelDatabase.redo_stack.clear()
	world=Main.instantiate()
	world.get_node("tutorial screen").start_delay=0.03
	world.get_node("SaveSystem").save_directory=OS.get_environment("ABCCAD_TEST_SAVE_DIR").path_join("saves")
	get_tree().root.add_child.call_deferred(world)
	await get_tree().create_timer(0.1).timeout
	await frames()
func _ready():
	get_node("/root/DriveUpload").endpoint=""
	var folder:="/private/tmp/abccad-startup-"+str(OS.get_process_id())
	OS.set_environment("ABCCAD_TEST_SAVE_DIR",folder)
	DirAccess.make_dir_recursive_absolute(folder)
	TutorialSettings.tutorial_seen=false
	left_tracker=tracker("left_hand",Vector3(-0.3,1.4,-0.5))
	right_tracker=tracker("right_hand",Vector3(0.3,1.4,-0.5))
	await restart()
	var wb=world.get_node("AdvancedCAD")
	check(wb.enabled and wb.panel.visible,"fresh installation opens CAD automatically")
	check(not world.get_node("Viewport2Din3D_tutorial").visible,"block intro never appears on default startup")
	check(not world.get_node("Viewport2Din3D").visible,"CAD startup skips the legacy main menu")
	check(not world.get_node("OmniLight3D5").visible and not world.get_node("OmniLight3D4").visible,"Front and Left lights default off")
	check(world.get_node("OmniLight3D2").visible and world.get_node("DirectionalLight3D").visible,"Right and directional lights retain their existing defaults")
	var before_lights: Dictionary=wb.document.snapshot()
	wb.toggle_scene_light("OmniLight3D5");wb.toggle_scene_light("OmniLight3D4")
	check(world.get_node("OmniLight3D5").visible and world.get_node("OmniLight3D4").visible and wb.document.snapshot()==before_lights,"Lights tab can re-enable Front and Left without changing geometry")

	for hand in [wb.left,wb.right]:
		check(hand.get_node(str(hand.name)+"/FunctionPointer").enabled,"CAD startup enables both pointer lasers")
	# Migrate the old default without interpreting enabled=false as a legacy opt-in.
	var cfg:=ConfigFile.new()
	cfg.set_value("cad","enabled",false)
	cfg.set_value("cad","probe_offset_mm",Vector3(1,2,-50))
	cfg.save(wb._settings_path())
	await restart();wb=world.get_node("AdvancedCAD")
	check(wb.enabled and wb.panel.visible,"existing old disabled setting upgrades to CAD-first startup")
	check(not world.get_node("OmniLight3D5").visible and not world.get_node("OmniLight3D4").visible,"relaunch restores the safe Front and Left defaults")
	check(wb.probe_offset_mm==Vector3(1,2,-50),"startup migration retains probe calibration")
	# With CAD temporarily closed, its mode must still own block-only controls.
	wb.close_panel()
	SignalBus.request_export_stl.connect(func():export_requests+=1)
	for value in [left_tracker,right_tracker]:
		await press(value,"ax_button")
		await press(value,"trigger_click")
	check(get_tree().get_nodes_in_group("abccad_blocks").is_empty(),"CAD mode never spawns legacy blocks when its panel is closed")
	check(export_requests==0,"CAD mode does not activate the legacy trigger-export shortcut")
	await press(left_tracker,"menu_button")
	check(world.get_node("Viewport2Din3D").visible,"left menu button still opens Settings access in CAD mode")
	var menu=world.get_node("Viewport2Din3D/Viewport").get_child(0)
	menu._sync_advanced_mode()
	check(menu.legacy_toggle.text=="Legacy block mode" and not menu.legacy_toggle.button_pressed,"Settings presents legacy as the opt-in mode")
	check(menu.advanced_button.text=="Return to CAD" and menu.advanced_button.visible,"main menu gives a clear return to CAD")
	var id: int=wb.document.new_sketch(Transform3D.IDENTITY)
	wb.document.set_profile(id,"rectangle",[[0,0],[10,10]],true)
	check(await wb.document.extrude(id,5,"New"),"create a CAD part before switching modes")
	var before: Dictionary=wb.document.snapshot()
	menu.legacy_toggle.button_pressed=true
	check(not wb.enabled and not wb.panel.visible,"Legacy setting disables CAD tools")
	check(wb.document.snapshot()==before,"switching to legacy preserves the CAD document")
	cfg.load(wb._settings_path())
	check(cfg.get_value("cad","legacy_mode",false) and cfg.get_value("cad","probe_offset_mm")==Vector3(1,2,-50),"explicit legacy choice saves without clearing calibration")
	await press(right_tracker,"ax_button")
	check(get_tree().get_nodes_in_group("abccad_blocks").size()==1,"legacy mode still spawns a block from real controller input")
	menu.legacy_toggle.button_pressed=false
	check(wb.enabled and wb.panel.visible and not world.get_node("Viewport2Din3D").visible,"switching back immediately reopens CAD")
	check(wb.document.snapshot()==before and get_tree().get_nodes_in_group("abccad_blocks").size()==1,"mode switching preserves both CAD and legacy content")
	cfg.load(wb._settings_path())
	check(not cfg.get_value("cad","legacy_mode",true),"CAD selection persists for the next launch")
	await restart();wb=world.get_node("AdvancedCAD")
	check(wb.enabled and wb.panel.visible and not world.get_node("Viewport2Din3D_tutorial").visible,"relaunch remembers CAD and still skips intro")
	wb.set_enabled(false)
	await restart();wb=world.get_node("AdvancedCAD")
	check(not wb.enabled and not wb.panel.visible,"relaunch respects an explicit saved legacy choice")
	check(world.get_node("Viewport2Din3D_tutorial").visible,"block tutorial is confined to legacy startup")
	wb.set_enabled(true);wb.open_panel()
	check(wb.panel.visible and not world.get_node("Viewport2Din3D_tutorial").visible,"opening CAD dismisses the legacy tutorial")
	check(not world.get_node("tutorial screen")._spawn_attempted,"dismissed tutorial cannot reappear over CAD")
	XRServer.remove_tracker(left_tracker);XRServer.remove_tracker(right_tracker)
	print("STARTUP RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
