extends XRController3D

@onready var my_pickup_function = $RightHand/FunctionPickup


@export var hand_material: StandardMaterial3D

@export var pickable_scene: PackedScene
@export var spawn_distance: float = 0.0

@export var spawn_action_name: StringName = "ax_button" # A button (spawn)
@export var color_cycle_action_name: StringName = "by_button" # B button (cycle color)
@export var export_action_name: StringName = "trigger_click" # Trigger (export STL)
@export var debug_logging: bool = true

# --- Block Type Switching ---
@export var block_scenes: Array[PackedScene] = []  # Assign in inspector: [cube.tscn, brick.tscn, etc.]
@export var joystick_deadzone: float = 0.5
var current_block_index: int = 0
var joystick_was_neutral: bool = true

# --- Color State ---
var colors := [Color.BLUE, Color.RED, Color.GREEN, Color.PINK, Color.YELLOW, Color.BLACK, Color.REBECCA_PURPLE]
var current_color_index := 0
var current_color: Color = Color.BLUE

# --- State Tracking ---
var _prev_spawn_pressed := false
var _prev_cycle_pressed := false
var _prev_export_pressed := false
var _ready_frame_passed := false
var held_cube: Node = null

# --- Export State ---
var export_cooldown: float = 0.0
const EXPORT_COOLDOWN_TIME: float = 1.5  # Prevent accidental double-exports


func _ready():
	add_to_group("block_controllers")
	await get_tree().process_frame
	_ready_frame_passed = true
	

	VoxelDatabase.voxel_placed.connect(_on_global_voxel_placed)

	if debug_logging:
		print("[XR] Controller ready:", name, 
			" spawn_action=", spawn_action_name, 
			" color_action=", color_cycle_action_name,
			" export_action=", export_action_name)
		print("[XR] Initial color:", current_color)
		
		
	_update_hand_color()
		
func _on_global_voxel_placed(_grid_pos, obj):
	if is_instance_valid(obj):
		BlockInteractions.connect_block(obj)


func _update_hand_color():
	print("[XR] Updating hand color to:", current_color)
	print("[XR] Hand material:", hand_material)
	if hand_material == null:
		return

	if hand_material is StandardMaterial3D:
		var sm := hand_material as StandardMaterial3D
		sm.albedo_color = current_color

	#elif hand_material is ShaderMaterial:
		#var sh := hand_material as ShaderMaterial
		# Try common parameter names – adjust to your shader
		#if "albedo_color" in sh.get_shader().get_param_list():
			#sh.set_shader_parameter("albedo_color", current_color)
		#elif "color" in sh.get_shader().get_param_list():
			#sh.set_shader_parameter("color", current_color)


func _process(delta: float) -> void:
	if not _ready_frame_passed or not is_inside_tree():
		return

	# Update export cooldown
	if export_cooldown > 0:
		export_cooldown -= delta

	# Check joystick for block type switching

	# Read XR button states directly from controller
	var spawn_pressed := is_button_pressed(spawn_action_name)
	var cycle_pressed := is_button_pressed(color_cycle_action_name)
	var export_pressed := is_button_pressed(export_action_name)
	var workbench = get_tree().get_first_node_in_group("cad_workbench")
	if workbench != null and workbench.enabled:
		_prev_spawn_pressed=spawn_pressed
		_prev_cycle_pressed=cycle_pressed
		_prev_export_pressed=export_pressed
		return
	_check_joystick_block_switch()

	# ALWAYS print B button state for debugging
	if cycle_pressed:
		print("[XR] !!! B BUTTON IS CURRENTLY PRESSED !!!")

	# Debug logging
	if debug_logging:
		if spawn_pressed != _prev_spawn_pressed:
			print("[XR] ", name, " button(", spawn_action_name, ") =", spawn_pressed)
		if cycle_pressed != _prev_cycle_pressed:
			print("[XR] ", name, " button(", color_cycle_action_name, ") =", cycle_pressed)
			print("[XR] B BUTTON STATE CHANGED! New state:", cycle_pressed)
		if export_pressed != _prev_export_pressed:
			print("[XR] ", name, " button(", export_action_name, ") =", export_pressed)

	# Handle spawning (A button)
	if spawn_pressed and not _prev_spawn_pressed:
		if debug_logging:
			print("[XR] Spawn triggered by", spawn_action_name)
		_spawn_cube()

	# Handle color cycling (B button)
	if cycle_pressed and not _prev_cycle_pressed:
		print("[XR] ========== COLOR CYCLE TRIGGERED ==========")
		if debug_logging:
			print("[XR] Color cycle triggered by", color_cycle_action_name)
		_cycle_color()

	# Handle export (Trigger)
	#if export_pressed and not _prev_export_pressed:
		#_on_trigger_pressed()

	# Remember button states
	_prev_spawn_pressed = spawn_pressed
	_prev_cycle_pressed = cycle_pressed
	_prev_export_pressed = export_pressed


# --- Block Type Switching ---
func _check_joystick_block_switch():
	if block_scenes.size() <= 1:
		return  # No point switching if there's only one or zero block types
	
	var joystick_x = get_vector2("primary").x # Get X axis of primary joystick
	
	# Check if joystick moved past deadzone
	if abs(joystick_x) > joystick_deadzone:
		if joystick_was_neutral:  # Only trigger once per movement
			if joystick_x > 0:  # Right
				_switch_block_type(1)
			else:  # Left
				_switch_block_type(-1)
			joystick_was_neutral = false
	else:
		joystick_was_neutral = true  # Reset when joystick returns to neutral


func _switch_block_type(direction: int):
	current_block_index += direction
	
	# Wrap around
	if current_block_index < 0:
		current_block_index = block_scenes.size() - 1
	elif current_block_index >= block_scenes.size():
		current_block_index = 0
	
	var block_name = "Unknown"
	if block_scenes[current_block_index]:
		block_name = block_scenes[current_block_index].resource_path.get_file().get_basename()
	
	print("[XR] 🔄 Block type switched to: ", block_name, " (index: ", current_block_index, ")")
	
	# Optional: Add haptic feedback
	trigger_haptic_pulse("haptic", 0, 0.3, 0.1, 0)
	
	# ⭐ NEW: Broadcast current block index to other systems (e.g. left hand)

	SignalBus.block_type_changed.emit(current_block_index)


# --- Spawning cubes ---
func _spawn_cube():
	# Use block_scenes array if available, otherwise fall back to pickable_scene
	var scene_to_use: PackedScene = null
	
	if block_scenes.size() > 0:
		if current_block_index >= block_scenes.size():
			current_block_index = 0
		scene_to_use = block_scenes[current_block_index]
		if scene_to_use == null:
			push_warning("Block scene at index ", current_block_index, " is null!")
			return
	elif pickable_scene != null:
		scene_to_use = pickable_scene
	else:
		push_warning("No scenes assigned for spawning!")
		return

	var cube := scene_to_use.instantiate()
	if cube == null:
		push_warning("Failed to instantiate scene.")
		return

	var shape_type := BlockInteractions.shape_for_scene(scene_to_use)
	cube.set_meta("shape_type", shape_type)

	# Spawn relative to controller
	var controller_basis := global_transform.basis
	var origin := global_transform.origin + (-controller_basis.z) * spawn_distance
	origin.y += 0.1

	# Add to XR Origin (so it stays in world space)
	var xr_origin := get_tree().root.get_node("Main/XROrigin3D")
	# Blocks belong to world space, independently of player locomotion/recentering.
	cube.top_level = true
	xr_origin.add_child(cube)
	cube.global_transform = Transform3D(controller_basis, origin)

	# Both hands must observe a block before its first placement.
	BlockInteractions.connect_block(cube)

	print("[XR] DEBUG: About to apply color:", current_color)
	
	# Apply color - find the MeshInstance3D child
	var mesh_instance = cube.get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.has_method("set_color"):
		mesh_instance.set_color(current_color)
		print("[XR] DEBUG: set_color() called on MeshInstance3D successfully")
	else:
		print("[XR] WARNING: MeshInstance3D not found or doesn't have set_color method!")
		print("[XR] DEBUG: Cube children:", cube.get_children())

	if debug_logging:
		print("[XR] Spawned", shape_type, "with color:", current_color)

	# Wake physics next frame if needed
	call_deferred("_wake_block", cube)


func _wake_block(block: Node):
	if not is_instance_valid(block) or block.is_queued_for_deletion(): return
	if block.has_method("set_sleeping"):
		block.set_sleeping(false)


# --- Color Cycling ---
func _cycle_color():
	print("[XR] DEBUG: _cycle_color() function called!")
	current_color_index = (current_color_index + 1) % colors.size()
	current_color = colors[current_color_index]
	
	print("[XR] DEBUG: New color index:", current_color_index)
	print("[XR] DEBUG: New current_color:", current_color)

	if is_instance_valid(held_cube) and held_cube.get_picked_up_by() == my_pickup_function:
		print("[XR] DEBUG: Held cube exists:", held_cube.name)
		var mesh_instance = held_cube.get_node_or_null("MeshInstance3D")
		if mesh_instance and mesh_instance.has_method("set_color"):
			mesh_instance.set_color(current_color)
			print("[XR] DEBUG: Applied color to held cube's MeshInstance3D")
		else:
			print("[XR] WARNING: Could not find MeshInstance3D in held cube")
			print("[XR] DEBUG: Held cube children:", held_cube.get_children())
	else:
		print("[XR] DEBUG: No held cube to change color")
		
	_update_hand_color()  # <<< add this

	if debug_logging:
		print("[XR] Color cycled to:", current_color)


func do_haptic_feedback():
	print("🧩 [HAPTICS] do_haptic_feedback() called")
	print("🧩 [HAPTICS] Controller:", name)
	trigger_haptic_pulse("haptic", 0.0, 0.1, 0.1, 0.0)
	print("🧩 [HAPTICS] Pulse sent successfully!")

func on_cube_grabbed(pickable: Node, by: Node3D):
	# ⭐ ROBUST CHECK: Is the grabber ('by') MY pickup function?
	if by != my_pickup_function:
		# It was grabbed by the other hand
		return

	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_grabbed() function called!")
	print("[HAPTIC DEBUG] Controller:", name)
	
	do_haptic_feedback()
	held_cube = pickable

func on_cube_released(pickable: Node, by: Node3D):
	# ⭐ ROBUST CHECK
	if by != my_pickup_function:
		return

	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_released() by ", name)
	
	do_haptic_feedback()

	BlockInteractions.finish_release.call_deferred(pickable, my_pickup_function)

	if held_cube == pickable:
		held_cube = null


# --- STL EXPORT ---
#func _on_trigger_pressed():
	#if export_cooldown > 0:
		#print("⏳ Export on cooldown, wait", snappedf(export_cooldown, 0.1), "seconds...")
		#return
	#
	#print("🎯 Right trigger pressed - starting export!")
	#_export_voxels_to_stl()
	#export_cooldown = EXPORT_COOLDOWN_TIME


func _export_voxels_to_stl():
	# Keep legacy callers on the same tested mesh exporter as the menu.
	SignalBus.request_export_stl.emit()
