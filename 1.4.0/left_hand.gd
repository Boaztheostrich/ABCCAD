extends XRController3D

@onready var my_pickup_function = $LeftHand/FunctionPickup

@export var pickable_scene: PackedScene
@export var spawn_distance: float = 0.0

@export var hand_material: StandardMaterial3D

@export var menu_action_name: StringName = "menu_button"

var _prev_menu_pressed := false

@export var spawn_action_name: StringName = "ax_button" # A button (spawn)
@export var color_cycle_action_name: StringName = "by_button" # B button (cycle color)
@export var export_action_name: StringName = "trigger_click" # Trigger (export STL)
@export var debug_logging: bool = true

# --- Block Type Switching ---
@export var block_scenes: Array[PackedScene] = []  # Assign in inspector: [cube.tscn, brick.tscn, etc.]
@export var joystick_deadzone: float = 0.5
@export var initial_delay: float = 0.6  # How long to hold before rapid-fire starts (seconds)
@export var repeat_rate: float = 0.05   # How fast to repeat once holding (seconds)
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

# --- INTERNAL STATE ---
var _repeat_timer: float = 0.0
var _current_dir: int = 0 # 0 = Neutral, -1 = Left, 1 = Right


func _ready():
	add_to_group("block_controllers")
	await get_tree().process_frame
	_ready_frame_passed = true
	
	VoxelDatabase.voxel_placed.connect(_on_global_voxel_placed)
	
		# ⭐ NEW: Listen for Load Game requests
	SignalBus.request_rebuild_block.connect(_on_load_game_block_requested)
	
	SignalBus.block_type_changed.connect(_on_block_type_changed)

	if debug_logging:
		print("[XR] Controller ready:", name, 
			" spawn_action=", spawn_action_name, 
			" color_action=", color_cycle_action_name,
			" export_action=", export_action_name)
		print("[XR] Initial color:", current_color)
		
	_update_hand_color()
		
func _update_hand_color():
	if hand_material == null:
		return
	hand_material.albedo_color = current_color
	
func _on_block_type_changed(new_index: int):
	# Right hand drives the index; left hand just mirrors it
	current_block_index = clamp(new_index, 0, block_scenes.size() - 1)
	if debug_logging:
		print("[XR][Left] Synced block index from right hand:", current_block_index)
		
func _on_global_voxel_placed(_grid_pos, obj):
	if is_instance_valid(obj):
		BlockInteractions.connect_block(obj)


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
	var menu_pressed := is_button_pressed(menu_action_name)
	
	if menu_pressed and not _prev_menu_pressed:
		print("[XR] Menu button pressed - Requesting Toggle")
		SignalBus.request_toggle_menu.emit()
		
	_prev_menu_pressed = menu_pressed
	var workbench = get_tree().get_first_node_in_group("cad_workbench")
	if workbench != null and workbench.enabled:
		_prev_spawn_pressed=spawn_pressed
		_prev_cycle_pressed=cycle_pressed
		_prev_export_pressed=export_pressed
		return
	_check_joystick_undo_redo(delta)

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
	if export_pressed and not _prev_export_pressed:
		_on_trigger_pressed()

	# Remember button states
	_prev_spawn_pressed = spawn_pressed
	_prev_cycle_pressed = cycle_pressed
	_prev_export_pressed = export_pressed


# --- Block Type Switching ---



func _check_joystick_undo_redo(delta: float):
	# Get X axis of primary joystick on Left Hand
	var joystick_x = get_vector2("primary").x 
	
	# Determine logical direction based on deadzone
	var new_dir = 0
	if joystick_x > joystick_deadzone:
		new_dir = 1  # Right (Redo)
	elif joystick_x < -joystick_deadzone:
		new_dir = -1 # Left (Undo)
	
	# --- CASE 1: INPUT RELEASED ---
	if new_dir == 0:
		_current_dir = 0
		_repeat_timer = 0.0
		return

	# --- CASE 2: NEW PRESS (OR DIRECTION CHANGE) ---
	if new_dir != _current_dir:
		_current_dir = new_dir
		_perform_action(new_dir) # Do it immediately
		_repeat_timer = initial_delay # Set wait time for the repeat start
		
	# --- CASE 3: HOLDING ---
	else:
		_repeat_timer -= delta
		if _repeat_timer <= 0.0:
			_perform_action(new_dir) # Repeat action
			_repeat_timer = repeat_rate # Reset short timer for next repeat

func _perform_action(direction: int):
	if direction == -1:
		# LEFT = UNDO
		VoxelDatabase.perform_undo(self)
		trigger_haptic_pulse("haptic", 0, 0.1, 0.05, 0) # Very light pulse for repeats
	elif direction == 1:
		# RIGHT = REDO
		VoxelDatabase.perform_redo(self)
		trigger_haptic_pulse("haptic", 0, 0.1, 0.05, 0)

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
		
	_update_hand_color()

	if debug_logging:
		print("[XR] Color cycled to:", current_color)


func do_haptic_feedback():
	print("🧩 [HAPTICS] do_haptic_feedback() called")
	print("🧩 [HAPTICS] Controller:", name)
	trigger_haptic_pulse("haptic", 0.0, 0.1, 0.1, 0.0)
	print("🧩 [HAPTICS] Pulse sent successfully!")

func on_cube_grabbed(pickable: Node, by: Node3D):
	# CRITICAL CHECK: Is the grabber ('by') actually THIS controller's pickup function?
	if by != my_pickup_function:
		return

	print("==================================================")
	print("[HAPTIC DEBUG] Grabbed by THIS controller: ", name)
	
	do_haptic_feedback()
	held_cube = pickable

func on_cube_released(pickable: Node, by: Node3D):
	# CRITICAL CHECK
	if by != my_pickup_function:
		return

	print("==================================================")
	print("[HAPTIC DEBUG] Released by THIS controller: ", name)
	
	do_haptic_feedback()

	BlockInteractions.finish_release.call_deferred(pickable, my_pickup_function)

	if held_cube == pickable:
		held_cube = null


# --- STL EXPORT ---
func _on_trigger_pressed():
	# An active UI pointer owns trigger clicks (Save/Load/Export/tutorial).
	# Do not also run the standalone export shortcut for those clicks.
	var pointer = get_node_or_null("LeftHand/FunctionPointer")
	if pointer != null and pointer.enabled:
		return

	if export_cooldown > 0:
		print("⏳ Export on cooldown, wait", snappedf(export_cooldown, 0.1), "seconds...")
		return
	
	print("🎯 Left trigger pressed - requesting shared STL export!")
	SignalBus.request_export_stl.emit()
	export_cooldown = EXPORT_COOLDOWN_TIME


func _export_voxels_to_stl():
	# Keep legacy callers on the same tested mesh exporter as the menu.
	SignalBus.request_export_stl.emit()

func _on_load_game_block_requested(grid_pos: Vector3i, shape_type: String, rotation: Basis, color: Color, exact_pos: Vector3):
	
	# We use the exact_pos passed from the save file
	# This makes the data packet IDENTICAL to the Undo/Redo packet!
	var data_packet = {
		"grid_pos": grid_pos,
		"shape_type": shape_type,
		"rotation": rotation,
		"color": color,
		"world_origin": exact_pos  # <--- USING THE SAVED "PHOTO" DATA
	}
	
	# Pass 'true' because we are loading
	restore_block_from_history(data_packet, true)
	#var world_pos = VoxelDatabase.grid_to_world(grid_pos)

	
	# Re-use your existing logic!
# This function is called by VoxelDatabase during Redo or Undo-Removal
func restore_block_from_history(data: Dictionary, is_loading_from_file: bool = false):
	var shape_type = data.shape_type
	var grid_pos = data.grid_pos
	var rotation = data.rotation
	var color = data.color
	
	print("🔄 REDO REQUEST: Type='", shape_type, "' at ", grid_pos)

	if VoxelDatabase.has_voxel(grid_pos):
		# Double check: Is it ACTUALLY occupied by a valid object?
		var blocking_obj = VoxelDatabase.get_voxel(grid_pos)
		if is_instance_valid(blocking_obj):
			print("⚠️ Skipping restore at ", grid_pos, ": Space is occupied by ", blocking_obj)
			return
		else:
			print("⚠️ Found Zombie node at ", grid_pos, " - Proceeding with overwrite.")
	
	var scene_to_spawn := BlockInteractions.find_scene(block_scenes, shape_type)

	if scene_to_spawn == null:
		print("❌ CRITICAL ERROR: Could not find a scene for shape_type: '", shape_type, "'")
		print("   Available scenes:", block_scenes)
		return

	# Instantiate
	var obj = scene_to_spawn.instantiate()
	obj.set_meta("shape_type", shape_type)
	var xr_origin = get_tree().root.get_node("Main/XROrigin3D") 
	obj.top_level = true
	xr_origin.add_child(obj)
	
	# --- DEBUGGING POSITION ---
	print("--- RESTORE DEBUG ---")
	print("Target Grid Pos: ", grid_pos)
	
	if data.has("world_origin"):
		print("✅ Using Exact Saved World Origin: ", data.world_origin)
		# Force the transform directly
		obj.global_transform = Transform3D(rotation, data.world_origin)
	else:
		var calc_pos = VoxelDatabase.grid_to_world(grid_pos)
		print("⚠️ Using Calculated Grid->World: ", calc_pos)
		obj.global_transform = Transform3D(rotation, calc_pos)

	# CHECK AFTER PLACEMENT
	print("ACTUAL Object Pos after placement: ", obj.global_position)
	
	# Apply Color
	var mesh = obj.get_node_or_null("MeshInstance3D")
	if mesh and mesh.has_method("set_color"):
		mesh.set_color(color)
		
	# Freeze physics
	if obj.has_method("set_sleeping"): obj.set_sleeping(true)
	if obj is RigidBody3D: obj.freeze = true
	
	# --- INTERNAL LOGIC CALL ---
	var is_complex_block = (shape_type == "brick" or shape_type == "m_cube")
	
	if is_complex_block:
		print("   ⚡ Triggering internal logic for COMPLEX block...")
		# Check root first, then children
		var script_target = obj
		if not obj.has_method("_on_dropped"):
			for child in obj.get_children():
				if child.has_method("_on_dropped"):
					script_target = child
					break
		
		# ... inside if is_complex_block: ...
	
		if script_target.has_method("_on_dropped"):
			if is_loading_from_file:
				print("   📂 LOADING: Skipping _on_dropped re-calculation. Trusting save file.")
				# We still need to register the master voxel manually here because we skipped _on_dropped
				VoxelDatabase.place_voxel(grid_pos, obj, shape_type, color, true, true)
			else:
				# THIS IS FOR UNDO/REDO (Keep original logic)
				print("   🔄 UNDO/REDO: Recalculating via _on_dropped...")
				script_target._on_dropped(null, true)
			
	else:
		print("   ℹ️ Simple block restore (Cube/Wedge).")
		VoxelDatabase.place_voxel(grid_pos, obj, shape_type, color, true, true)
		# Re-grabbing a history-restored simple block must remove its old cell.
		var voxel_logic = obj.get_node_or_null("VoxelLogic")
		if voxel_logic != null:
			voxel_logic.last_grid_positions.assign([grid_pos])
