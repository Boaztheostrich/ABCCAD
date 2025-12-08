extends Button

func _ready():
	print("🔍 UI BUTTON: I am ready and active in the scene!")
	# Double check the signal connection in code just in case
	if not pressed.is_connected(_on_pressed):
		print("⚠️ UI BUTTON: 'pressed' signal was NOT connected in editor. Connecting via code now...")
		pressed.connect(_on_pressed)
	else:
		print("✅ UI BUTTON: 'pressed' signal is correctly connected.")

func _on_pressed():
	print("🔴 UI BUTTON: I WAS CLICKED!") 
	print("    -> Sending signal to SignalBus...")
	SignalBus.request_export_stl.emit()
	print("    -> Signal emitted.")
