extends Control

signal request_close

@onready var close_button := $ColorRect/MarginContainer/MainMenu/HBoxContainer/CloseButton
@onready var never_button := $ColorRect/MarginContainer/MainMenu/HBoxContainer/NeverShowButton

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	never_button.pressed.connect(_on_never_show_pressed)

func _on_close_pressed():
	request_close.emit(false) # just close this session
	queue_free()

func _on_never_show_pressed():
	TutorialSettings.mark_tutorial_seen()
	request_close.emit(true) # closed + never again
	queue_free()
