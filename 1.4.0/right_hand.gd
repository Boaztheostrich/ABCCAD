extends XRController3D

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
	await get_tree().process_frame
	_ready_frame_passed = true

	if debug_logging:
		print("[XR] Controller ready:", name, 
			" spawn_action=", spawn_action_name, 
			" color_action=", color_cycle_action_name,
			" export_action=", export_action_name)
		print("[XR] Initial color:", current_color)


func _process(delta: float) -> void:
	if not _ready_frame_passed or not is_inside_tree():
		return

	# Update export cooldown
	if export_cooldown > 0:
		export_cooldown -= delta

	# Check joystick for block type switching
	_check_joystick_block_switch()

	# Read XR button states directly from controller
	var spawn_pressed := is_button_pressed(spawn_action_name)
	var cycle_pressed := is_button_pressed(color_cycle_action_name)
	var export_pressed := is_button_pressed(export_action_name)

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

	print("[XR] DEBUG: Cube instantiated, type:", cube.get_class())
	
	# Spawn relative to controller
	var controller_basis := global_transform.basis
	var origin := global_transform.origin + (-controller_basis.z) * spawn_distance
	origin.y += 0.1
	cube.global_transform = Transform3D(controller_basis, origin)

	# Add to XR Origin (so it stays in world space)
	var xr_origin := get_tree().root.get_node("Main/XROrigin3D")
	xr_origin.add_child(cube)
	cube.set_as_top_level(false)

	# Connect grab signals
	if cube.has_signal("grabbed"):
		cube.grabbed.connect(on_cube_grabbed.bind(cube))
		print("[XR] DEBUG: Connected to grabbed signal")
	if cube.has_signal("released"):
		cube.released.connect(on_cube_released.bind(cube))
		print("[XR] DEBUG: Connected to released signal")

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
		print("[XR] Spawned cube with color:", current_color)

	# Wake physics next frame if needed
	call_deferred("_wake_block", cube)


func _wake_block(block: Node):
	if block.has_method("set_sleeping"):
		block.set_sleeping(false)


# --- Color Cycling ---
func _cycle_color():
	print("[XR] DEBUG: _cycle_color() function called!")
	current_color_index = (current_color_index + 1) % colors.size()
	current_color = colors[current_color_index]
	
	print("[XR] DEBUG: New color index:", current_color_index)
	print("[XR] DEBUG: New current_color:", current_color)

	if held_cube:
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

	if debug_logging:
		print("[XR] Color cycled to:", current_color)


func do_haptic_feedback():
	print("🧩 [HAPTICS] do_haptic_feedback() called")
	print("🧩 [HAPTICS] Controller:", name)
	trigger_haptic_pulse("haptic", 0.0, 0.1, 0.1, 0.0)
	print("🧩 [HAPTICS] Pulse sent successfully!")

func on_cube_grabbed(pickable: Node, by: Node3D, grab_info: Object):
	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_grabbed() function called!")
	print("[HAPTIC DEBUG] Pickable:", pickable.name if pickable else "NULL")
	print("[HAPTIC DEBUG] Grabbed by:", by.name if by else "NULL")
	print("[HAPTIC DEBUG] Grab Info object:", grab_info)
	do_haptic_feedback()
	print("[HAPTIC DEBUG] Haptic feedback triggered on grab.")
	print("==================================================")

	held_cube = pickable
	var mesh_instance = pickable.get_node_or_null("MeshInstance3D")
	#if mesh_instance and mesh_instance.has_method("get_color"):
		#current_color = mesh_instance.get_color()
	#if debug_logging:
		#print("[XR] Grabbed cube, syncing color to:", current_color)

func on_cube_released(pickable: Node, by: Node3D, grab_info: Object):
	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_released() function called!")
	print("[HAPTIC DEBUG] Pickable:", pickable.name if pickable else "NULL")
	print("[HAPTIC DEBUG] Released by:", by.name if by else "NULL")
	print("[HAPTIC DEBUG] Grab Info object:", grab_info)
	do_haptic_feedback()
	print("[HAPTIC DEBUG] Haptic feedback triggered on release.")
	print("==================================================")

	if held_cube == pickable:
		if debug_logging:
			print("[XR] Released cube.")
		held_cube = null


# --- STL EXPORT ---
func _on_trigger_pressed():
	if export_cooldown > 0:
		print("⏳ Export on cooldown, wait", snappedf(export_cooldown, 0.1), "seconds...")
		return
	
	print("🎯 Right trigger pressed - starting export!")
	_export_voxels_to_stl()
	export_cooldown = EXPORT_COOLDOWN_TIME


func _export_voxels_to_stl():
	var voxel_count = VoxelDatabase.get_voxel_count()
	
	if voxel_count == 0:
		print("❌ No voxels to export! Place some cubes first.")
		return
	
	print("📦 Exporting", voxel_count, "voxels...")
	
	# Create surface tool for combining
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Get all voxel grid positions
	var grid_positions = VoxelDatabase.get_all_voxels()
	
	# For each voxel, add its cube geometry
	for grid_pos in grid_positions:
		var world_pos = VoxelDatabase.grid_to_world(grid_pos)
		var voxel_obj = VoxelDatabase.get_voxel(grid_pos)
		
		if voxel_obj and is_instance_valid(voxel_obj):
			_add_cube_to_surface(st, world_pos, VoxelDatabase.voxel_size)
	
	# Commit the combined mesh
	var combined_mesh := st.commit()
	print("✅ Mesh combined with", combined_mesh.get_surface_count(), "surface(s)")
	
	# 🆕 Get the Downloads folder path (cross-platform)
	var downloads_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	
	# Create timestamped filename
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var filename = "voxel_build_" + timestamp + ".stl"
	var file_path: String = downloads_path.path_join(filename)
	
	var result = STLIO.Exporter.SaveToPath(combined_mesh, file_path)
	
	if result == OK:
		print("✅✅✅ STL EXPORTED SUCCESSFULLY! ✅✅✅")
		print("📂 Saved to Downloads folder:")
		print("   ", file_path)
		print("📊 Total voxels exported:", voxel_count)
	else:
		print("❌ Export failed with error:", result)
		print("   Attempted path:", file_path)


# Helper function to add a cube at a specific position
func _add_cube_to_surface(st: SurfaceTool, pos: Vector3, size: float):
	# Define unit cube vertices
	var verts = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)
	]
	
	# Scale and position them
	for i in range(verts.size()):
		verts[i] = verts[i] * size + pos
	
	# Define faces (each face = 2 triangles = 6 vertex indices)
	var faces = [
		[0, 2, 1,  0, 3, 2],  # Front
		[5, 7, 4,  5, 6, 7],  # Back
		[4, 3, 0,  4, 7, 3],  # Left
		[1, 6, 5,  1, 2, 6],  # Right
		[3, 6, 2,  3, 7, 6],  # Top
		[4, 1, 5,  4, 0, 1]   # Bottom
	]
	# Add all triangles
	for face in faces:
		for idx in face:
			var vert = verts[idx]
			st.add_vertex(vert)
