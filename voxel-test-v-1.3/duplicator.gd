extends Node3D

@export var cube_scene: PackedScene        # assign your cube scene here
var is_held := false

func _ready():
	var parent = get_parent()
	if parent.has_signal("grabbed"):
		parent.connect("grabbed", Callable(self, "_on_grabbed"))
	if parent.has_signal("dropped"):
		parent.connect("dropped", Callable(self, "_on_dropped"))

func _on_grabbed(_by):
	is_held = true

func _on_dropped(_by):
	is_held = false

func _process(_delta):
	# Only duplicate if cube is being held and button pressed
	if is_held and Input.is_action_just_pressed("vr_duplicate"):
		duplicate_cube()

func duplicate_cube():
	if cube_scene == null:
		push_warning("Cube scene not set in Inspector.")
		return

	var parent_cube = get_parent()
	var new_cube = cube_scene.instantiate()
	new_cube.global_transform = parent_cube.global_transform
	get_tree().current_scene.add_child(new_cube)

	# Wake the new cube so it behaves like a fresh object
	if new_cube.has_method("set_sleeping"):
		new_cube.set_sleeping(false)

	print("🧱 Duplicated cube at:", new_cube.global_position)
