extends Node

# Observe native OpenXR input without invoking gameplay actions.
var tracked: Array[Node3D] = []
var previous: Dictionary = {}
var elapsed := 0.0

func _ready():
	var world := get_parent()
	world.get_node("SaveSystem").save_directory = "/private/tmp/abccad-native-input-saves"
	for path in ["XROrigin3D/XRCamera3D", "XROrigin3D/LeftHand", "XROrigin3D/RightHand"]:
		var device = world.get_node_or_null(path)
		if device:
			tracked.append(device)
			if device is XRController3D:
				device.button_pressed.connect(func(action): print("NATIVE BUTTON ", device.name, " ", action))
	print("NATIVE OBSERVER READY: no scripted gameplay or pose changes")
	if "--fixtures" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.0).timeout
		for device in tracked:
			if not device is XRController3D:
				continue
			var block = preload("res://brick.tscn").instantiate()
			block.freeze = true
			block.set_meta("shape_type", "brick")
			world.add_child(block)
			block.global_transform = device.global_transform
			BlockInteractions.connect_block(block)
			block.grabbed.connect(func(_block, by): print("NATIVE GRAB ", by.name, " ", _block.name))
			block.released.connect(func(_block, by): print("NATIVE RELEASE ", by.name, " ", _block.name))
		print("FIXTURES READY: two stationary bricks at initial controller positions; user input controls grabs")

func _process(delta):
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0.0
	for device in tracked:
		var pose := device.global_transform
		if previous.has(device.name):
			var old: Transform3D = previous[device.name]
			if pose.origin.distance_to(old.origin) > 0.005 or pose.basis.get_rotation_quaternion().angle_to(old.basis.get_rotation_quaternion()) > 0.01:
				print("NATIVE POSE ", device.name, " position=", pose.origin, " rotation=", pose.basis.get_euler())
		previous[device.name] = pose
