extends Button

func _ready():
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed():
	print("📂 UI: Load Menu Button Clicked") 
	# This should probably toggle visibility of your file list panel
	SignalBus.request_toggle_menu.emit("load_menu")
