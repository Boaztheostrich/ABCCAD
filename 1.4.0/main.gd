extends Node3D

@onready var world_environment: WorldEnvironment = $WorldEnvironment

var xr_interface: OpenXRInterface

func _ready():
	await get_tree().process_frame
	
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		
		# Turn off v-sync!
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
		# Change our main viewport to output to the HMD
		get_viewport().use_xr = true
		
		# Connect to the pose_recentered signal
		xr_interface.pose_recentered.connect(_on_pose_recentered)
		print("Connected to pose_recentered signal")
		
		# Enable passthrough on startup
		_enable_passthrough(true)
	else:
		print("OpenXR not initialized, please check if your headset is connected")


func _on_pose_recentered():
	print("Recenter requested!")
	
	# This will move the player so the camera is at the origin
	# keeping tilt and maintaining height
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	
	print("Player recentered at origin")


func _enable_passthrough(enable: bool) -> void:
	# Enable passthrough if true and XR_ENV_BLEND_MODE_ALPHA_BLEND is supported.
	# Otherwise, set environment to non-passthrough settings.
	if enable and xr_interface.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		get_viewport().transparent_bg = true
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		print("Passthrough enabled")
	else:
		get_viewport().transparent_bg = false
		world_environment.environment.background_mode = Environment.BG_SKY
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		print("Passthrough disabled or not supported")
