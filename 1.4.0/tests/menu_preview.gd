extends Node

func _ready():
	DisplayServer.window_set_title("ABCCAD — Save / Load Preview")
	var saver := preload("res://SaveSystem.gd").new()
	saver.save_directory = "/private/tmp/abccad-menu-preview-saves"
	add_child(saver)
	var player := preload("res://player.tscn").instantiate()
	# The preview exercises production button handlers and save validation.
	add_child(player)
	var menu := preload("res://Menu_screen_0.tscn").instantiate()
	add_child(menu)
	menu.save_folder_path = saver.save_directory
	await get_tree().process_frame
	SignalBus.request_toggle_menu.emit()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/private/tmp/abccad-menu-main.png")
		menu.btn_save.pressed.emit()
		menu.btn_to_load_screen.pressed.emit()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/private/tmp/abccad-menu-load.png")
		get_tree().quit()
