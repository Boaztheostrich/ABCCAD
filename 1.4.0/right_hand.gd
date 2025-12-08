extends XRController3D

@onready var my_pickup_function = $RightHand/FunctionPickup

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
	

	VoxelDatabase.voxel_placed.connect(_on_global_voxel_placed)

	if debug_logging:
		print("[XR] Controller ready:", name, 
			" spawn_action=", spawn_action_name, 
			" color_action=", color_cycle_action_name,
			" export_action=", export_action_name)
		print("[XR] Initial color:", current_color)
		
func _on_global_voxel_placed(grid_pos, obj):
	if not is_instance_valid(obj): return
	
	# Check if we already connected to avoid duplicates
	if obj.is_connected("grabbed", on_cube_grabbed):
		return
		
	# Connect our local handlers
	if obj.has_signal("grabbed"):
			obj.grabbed.connect(on_cube_grabbed.bind(obj))
	if obj.has_signal("released"):
		obj.released.connect(on_cube_released.bind(obj))
		
	print("[XR] Hand connected to new/restored block: ", obj.name)


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

	# ⭐ NEW: Detect the shape type from the scene name
# ⭐ UPDATED: Detect the shape type including BRICK
	var shape_type = "cube"
	var scene_name = scene_to_use.resource_path.get_file().get_basename().to_lower()
	
	if "brick" in scene_name:       # <--- ADD THIS
		shape_type = "brick"
	elif "wedge" in scene_name or "triangle" in scene_name:
		shape_type = "wedge"
	elif "corner" in scene_name:
		shape_type = "corner_wedge"
	elif "m_cube" in scene_name:
		shape_type = "m_cube"
	
	# Store that info inside the node
	cube.set_meta("shape_type", shape_type)
	print("[XR] DEBUG: Spawning shape type:", shape_type)
	
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
		print("[XR] Spawned", shape_type, "with color:", current_color)

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
	# ⭐ ROBUST CHECK: Is the grabber ('by') MY pickup function?
	if by != my_pickup_function:
		# It was grabbed by the other hand
		return

	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_grabbed() function called!")
	print("[HAPTIC DEBUG] Controller:", name)
	
	do_haptic_feedback()
	held_cube = pickable

func on_cube_released(pickable: Node, by: Node3D, grab_info: Object):
	# ⭐ ROBUST CHECK
	if by != my_pickup_function:
		return

	print("==================================================")
	print("[HAPTIC DEBUG] on_cube_released() by ", name)
	
	do_haptic_feedback()

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
	
	var cube_count = 0
	var wedge_count = 0
	var corner_wedge_count = 0
	
	# Handle different shape types
	for grid_pos in grid_positions:
		var world_pos = VoxelDatabase.grid_to_world(grid_pos)
		var voxel_data = VoxelDatabase.get_voxel_data(grid_pos)
		
		if voxel_data and is_instance_valid(voxel_data.object):
			print("  🔧 Exporting", voxel_data.shape_type, "at grid:", grid_pos, "world:", world_pos)
			
			match voxel_data.shape_type:
				"cube":
					_add_cube_to_surface(st, world_pos, VoxelDatabase.voxel_size)
					cube_count += 1
					print("    ✅ Added cube")
				"corner_wedge":
					print("    🔺 Corner wedge rotation basis:", voxel_data.rotation)
					_add_corner_wedge_to_surface(st, world_pos, VoxelDatabase.voxel_size, voxel_data.rotation)
					corner_wedge_count += 1
					print("    ✅ Added corner wedge")
				"wedge":
					print("    🔺 Wedge rotation basis:", voxel_data.rotation)
					_add_wedge_to_surface(st, world_pos, VoxelDatabase.voxel_size, voxel_data.rotation)
					wedge_count += 1
					print("    ✅ Added wedge")
				_:
					print("⚠️ Unknown shape type:", voxel_data.shape_type, "at", grid_pos)
	
	print("📊 Export summary: ", cube_count, "cubes, ", wedge_count, "wedges", corner_wedge_count, "corner wedges")
	
	# Commit the combined mesh
	var combined_mesh := st.commit()
	print("✅ Mesh combined with", combined_mesh.get_surface_count(), "surface(s)")
	
	# Get the Downloads folder path (cross-platform)
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

# ⭐ NEW: Helper function to add a corner wedge at a specific position with rotation
# ⭐ NEW: Helper function to add a corner wedge (Pyramid style)
# ⭐ NEW: Helper function to add a corner wedge (Pyramid style) with 3-Axis Correction
# ⭐ NEW: Helper function with SEPARATED Tilt and Spin corrections
# ⭐ NEW: Helper function with CORRECTED Rotation Order
func _add_corner_wedge_to_surface(
	st: SurfaceTool,
	pos: Vector3,
	size: float,
	rotation: Basis
):
	var half_size = size * 0.5
	var center = pos + Vector3(half_size, half_size, half_size)
	
	# --- 1. DEFINE GEOMETRY ---
	# Peak at Top-Left-Back
	var peak = Vector3(-0.5, 0.5, -0.5)
	var bot_back_left = Vector3(-0.5, -0.5, -0.5)
	var bot_back_right = Vector3(0.5, -0.5, -0.5)
	var bot_fwd_right = Vector3(0.5, -0.5, 0.5)
	var bot_fwd_left = Vector3(-0.5, -0.5, 0.5)
	
	var verts = [peak, bot_back_left, bot_back_right, bot_fwd_right, bot_fwd_left]
	
	# --- 2. APPLY CORRECTION ---
	var x_tilt = 270.0   # Keeps it standing up (Good!)
	var y_spin = 90.0    # NOW this will spin it like a turntable. Try 0, 90, 180, 270.
	
	var tilt_basis = Basis(Vector3.RIGHT, deg_to_rad(x_tilt))
	var spin_basis = Basis(Vector3.UP, deg_to_rad(y_spin))
	
	# ⭐ KEY CHANGE HERE: Apply Spin FIRST, then Tilt.
	# This ensures we rotate the shape correctly BEFORE standing it up.
	var correction_basis = tilt_basis * spin_basis
	
	# --- 3. TRANSFORM VERTICES ---
	for i in range(verts.size()):
		var v = verts[i]
		
		# A. Apply Correction
		v = correction_basis * v
		
		# B. Scale
		v = v * size
		
		# C. Apply World Rotation
		v = rotation * v
		
		# D. Move to Center
		verts[i] = v + center
	
	# Re-assign
	peak = verts[0]
	bot_back_left = verts[1]
	bot_back_right = verts[2]
	bot_fwd_right = verts[3]
	bot_fwd_left = verts[4]
	
	# --- 4. FACES ---
	var triangles = [
		[bot_back_left, bot_fwd_right, bot_back_right],
		[bot_back_left, bot_fwd_left, bot_fwd_right],
		[bot_back_left, peak, bot_back_right],
		[bot_back_left, bot_fwd_left, peak],
		[peak, bot_back_right, bot_fwd_right],
		[peak, bot_fwd_right, bot_fwd_left]
	]
	
	for tri in triangles:
		for vert in tri:
			st.add_vertex(vert)

# ⭐ NEW: Helper function to add a wedge at a specific position with rotation
func _add_wedge_to_surface(
	st: SurfaceTool,
	pos: Vector3, # This is the voxel CORNER provided by grid_to_world
	size: float,
	rotation: Basis
):
	# Calculate the center of the voxel
	var half_size = size * 0.5
	var center = pos + Vector3(half_size, half_size, half_size)

	# Define vertices relative to the CENTER (range -0.5 to 0.5)
	# This corresponds to your wedge shape (Slope goes down from Left to Right)
	var verts = [
		Vector3(0.5, -0.5, -0.5),  # 0: bottom right back
		Vector3(0.5, -0.5, 0.5),   # 1: bottom right front
		Vector3(-0.5, -0.5, 0.5),  # 2: bottom left front
		Vector3(-0.5, -0.5, -0.5), # 3: bottom left back
		Vector3(-0.5, 0.5, -0.5),  # 4: top left back
		Vector3(-0.5, 0.5, 0.5),   # 5: top left front
	]

	# Apply Rotation and Position
	for i in range(verts.size()):
		# 1. Scale 
		var v = verts[i] * size
		
		# 2. Rotate around the center (local 0,0,0)
		v = rotation * v
		
		# 3. Move to the voxel's world center
		verts[i] = v + center

	# Define Faces (Triangle indices)
	var triangles = [
		# Bottom Face
		[0, 2, 1],
		[0, 3, 2],
		# Sloped Face
		[3, 5, 2],
		[3, 4, 5],
		# Vertical Face (Back)
		[3, 4, 0],
		# Vertical Face (Front)
		[2, 5, 1],
		# Vertical Face (Right side - the tall side)
		[0, 4, 5],
		[0, 5, 1],
	]

	for tri in triangles:
		for idx in tri:
			st.add_vertex(verts[idx])
