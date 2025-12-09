extends Node

# Assign these in the Inspector!
@export var menu_root: Node3D       
@export var xr_camera: XRCamera3D   
@export var pointers: Array[Node3D] 

@export var distance_from_face: float = 1.5
@export var height_offset: float = -0.2 

# CHANGED: Increased to 3.0 to ensure headset creates the "room" first
@export var start_delay: float = 3.0 

var _spawn_attempted: bool = false

func _ready():
	#SignalBus.request_toggle_menu.connect(_toggle_menu)
	
	if menu_root:
		menu_root.visible = false
		print("🕵️ DEBUG: MenuManager Ready. Menu hidden. Waiting ", start_delay, " seconds...")
	
	_set_pointers_enabled(false)
	
	# Wait longer to clear the "Oculus Black Screen" load
	await get_tree().create_timer(start_delay).timeout
	
	print("🕵️ DEBUG: Timer finished. Attempting to summon menu now...")
	if menu_root:
		_summon_menu()
		_set_pointers_enabled(true)
		_spawn_attempted = true # Start the watchdog

# --- WATCHDOG DEBUGGER ---
# This runs every frame to see if something else hides your menu
func _process(_delta):
	if _spawn_attempted and menu_root:
		if menu_root.visible == false:
			print("❌ DEBUG ALERT: The menu became invisible AFTER spawn!")
			print("   -> Did you press a button? Or did another script hide it?")
			_spawn_attempted = false # Stop spamming logs
# -------------------------

func _toggle_menu():
	if not menu_root: return
	
	if not menu_root.visible:
		print("🔘 Toggle Request: Opening Menu")
		_summon_menu()
		_set_pointers_enabled(true)
		_spawn_attempted = true
	else:
		print("🔘 Toggle Request: Closing Menu")
		menu_root.visible = false
		_set_pointers_enabled(false)
		_spawn_attempted = false

func _summon_menu():
	if not xr_camera: return

	var head_pos = xr_camera.global_position
	var head_basis = xr_camera.global_transform.basis
	
	var forward_vector = -head_basis.z
	forward_vector.y = 0 
	forward_vector = forward_vector.normalized()
	
	var target_pos = head_pos + (forward_vector * distance_from_face)
	target_pos.y += height_offset
	
	menu_root.global_position = target_pos
	menu_root.look_at(2 * target_pos - head_pos, Vector3.UP)
	
	menu_root.visible = true
	
	# Force it to stay visible for this frame to be sure
	menu_root.show() 
	
	print("📂 Menu Summoned at:", target_pos)
	print("   -> Distance from Head:", head_pos.distance_to(target_pos))
	print("   -> Visible State is now: boaz turotial menu", menu_root.visible)

func _set_pointers_enabled(enabled: bool):
	for ptr in pointers:
		if ptr:
			ptr.visible = enabled
			ptr.set_process(enabled)
			if "enabled" in ptr:
				ptr.enabled = enabled
