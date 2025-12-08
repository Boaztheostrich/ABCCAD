extends Button

func _ready():
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed():
	print("💾 UI: Save Button Clicked") 
	# We pass 'null' as the filename to let the system generate a timestamp name
	SignalBus.request_save_game.emit("") 
	
	# Optional: Give feedback on the button text
	var original_text = text
	text = "Saved!"
	disabled = true
	await get_tree().create_timer(1.0).timeout
	text = original_text
	disabled = false
