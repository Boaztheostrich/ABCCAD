extends Node

@export var delay: float = 3.0

func _ready():
	print("⏳ AutoStart: Waiting ", delay, " seconds...")
	
	# 1. Wait for headset to initialize
	await get_tree().create_timer(delay).timeout
	
	# 2. "Press" the button programmatically
	print("🤖 AutoStart: Simulating Menu Button Press now!")
	SignalBus.request_toggle_menu.emit()
