extends Node

# Assign these in the Inspector!
@export var menu_root: Node3D       # The parent node of your Viewport2Din3D
@export var xr_camera: XRCamera3D   # Your Head/Camera
@export var pointers: Array[Node3D] # Drag your FunctionPointer nodes here (Left and Right)

@export var distance_from_face: float = 1.5
@export var height_offset: float = -0.2 # Lower it slightly so it's comfortable

func _ready():
	# Listen for the toggle request
	SignalBus.request_toggle_menu.connect(_toggle_menu)
	
	# Start with menu hidden and pointers off
	if menu_root:
		menu_root.visible = false
	
	_set_pointers_enabled(false)

func _toggle_menu():
	if not menu_root or not xr_camera:
		print("⚠️ Error: Menu Root or Camera not assigned in MenuManager!")
		return
	
	# If currently hidden, show it and move it
	if not menu_root.visible:
		_summon_menu()
		_set_pointers_enabled(true)
	else:
		menu_root.visible = false
		_set_pointers_enabled(false)

func _summon_menu():
	# 1. Get Head Position
	var head_pos = xr_camera.global_position
	var head_basis = xr_camera.global_transform.basis
	
	# 2. Calculate point in front of face (Forward is -Z)
	var forward_vector = -head_basis.z
	# Flatten the vector so the menu doesn't tilt up/down wildly if you look up/down
	forward_vector.y = 0 
	forward_vector = forward_vector.normalized()
	
	var target_pos = head_pos + (forward_vector * distance_from_face)
	target_pos.y += height_offset
	
	# 3. Apply Position
	menu_root.global_position = target_pos
	
	# 4. Make it look at the player
	# note: look_at makes the -Z axis point at target. 
	# UI Planes usually face +Z. So we look at a point *behind* the menu to flip it.
	menu_root.look_at(2 * target_pos - head_pos, Vector3.UP)
	
	menu_root.visible = true
	print("📂 Menu Summoned at:", target_pos)

func _set_pointers_enabled(enabled: bool):
	for ptr in pointers:
		if ptr:
			# Usually XRToolsFunctionPointer has an 'enabled' property 
			# or simply set process/visible
			ptr.visible = enabled
			ptr.set_process(enabled)
			# Sometimes you need to toggle the Laser node inside specifically
			# If using XRTools, set the "enabled" property:
			if "enabled" in ptr:
				ptr.enabled = enabled
