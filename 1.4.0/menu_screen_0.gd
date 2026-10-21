extends Control

# --- EXPORTS: Structural containers ---
@export_group("Containers")
@export var main_menu_container: Control
@export var load_menu_container: Control
@export var file_list_container: VBoxContainer

# --- BUTTON VARIABLES ---
var btn_export: Button
var btn_save: Button
var btn_to_load_screen: Button
var btn_load_confirm: Button
var btn_delete: Button
var btn_back: Button
var scroll_container: ScrollContainer

# --- STATE ---
var selected_file_name: String = ""
var save_folder_path = "user://saves/"
var advanced_button: Button
var legacy_toggle: CheckButton
var settings_panel: PanelContainer
var status_label: Label
var load_status_label: Label

func _ready():
	print("🔍 UI: Initializing Menu Controller...")

	# 1. FIND NODES MANUALLY
	btn_export = find_child("Export to STL", true, false)
	btn_save = find_child("Save Button", true, false)
	btn_to_load_screen = find_child("Load Button", true, false)
	
	btn_load_confirm = find_child("Load Selected", true, false)
	btn_delete = find_child("Delete", true, false)
	btn_back = find_child("Back", true, false)
	scroll_container = find_child("ScrollContainer", true, false)

	# 2. Check Directory
	if not DirAccess.dir_exists_absolute(save_folder_path):
		DirAccess.make_dir_absolute(save_folder_path)

	# 3. Connect Buttons
	if btn_export: btn_export.pressed.connect(_on_export_pressed)
	if btn_save: btn_save.pressed.connect(_on_save_pressed)
	if btn_to_load_screen: btn_to_load_screen.pressed.connect(_show_load_menu)
	if btn_back: btn_back.pressed.connect(_show_main_menu)
	if btn_load_confirm: btn_load_confirm.pressed.connect(_on_load_confirm_pressed)
	if btn_delete: btn_delete.pressed.connect(_on_delete_pressed)
	
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 48
	status_label.add_theme_font_size_override("font_size", 28)
	find_child("MainMenu", true, false).add_child(status_label)
	load_status_label = status_label.duplicate()
	find_child("LoadMenu", true, false).get_node("VBoxContainer").add_child(load_status_label)
	SignalBus.save_finished.connect(_on_save_finished)
	SignalBus.load_finished.connect(_on_load_finished)
	SignalBus.export_finished.connect(_on_export_finished)
	var up_button := find_child("Scroll Up", true, false) as Button
	var down_button := find_child("Scroll Down", true, false) as Button
	if up_button: up_button.pressed.connect(func(): scroll_container.scroll_vertical -= 180)
	if down_button: down_button.pressed.connect(func(): scroll_container.scroll_vertical += 180)
	_update_action_buttons()
	_build_settings()

	# 4. LISTEN TO SIGNAL (Re-enabled!)
	SignalBus.request_toggle_menu.connect(_toggle_visibility)

	# 5. INITIAL STATE: Start HIDDEN so the first click Opens it
	# This prevents the "Invisible Box" issue by ensuring the first OPEN action
	# triggers the full layout calculation.
	visible = false 
	
	print("✅ UI: Setup Complete. Menu is ready (Hidden).")

# --- NAVIGATION ---

func _toggle_visibility():
	# If visible -> Hide. If hidden -> Show.
	var target_state = !visible
	
	if target_state == true:
		# 1. Activate
		visible = true
		_show_main_menu()
		
		# 2. FORCE LAYOUT (The fix for VR sizing bugs)
		set_anchors_preset(Control.PRESET_FULL_RECT)
		force_update_transform()
		
		print("📂 UI: Menu OPENED")
	else:
		visible = false
		print("📂 UI: Menu CLOSED")

func _show_main_menu():
	if settings_panel: settings_panel.visible=false
	_sync_advanced_mode()
	# Force visibility on containers directly found
	var mm = find_child("MainMenu", true, false)
	var lm = find_child("LoadMenu", true, false)
	
	if mm: 
		mm.visible = true
		mm.set_process_input(true)
	if lm: 
		lm.visible = false

func _show_load_menu():
	# Force visibility on containers directly found
	var mm = find_child("MainMenu", true, false)
	var lm = find_child("LoadMenu", true, false)

	if mm: mm.visible = false
	if lm: lm.visible = true
	_refresh_file_list()

# --- MAIN MENU ACTIONS ---

func _on_export_pressed():
	print("UI: Requesting Export")
	SignalBus.request_export_stl.emit()

func _on_save_pressed():
	if btn_save.disabled: return
	btn_save.disabled = true
	SignalBus.request_save_game.emit("")

func _on_save_finished(success: bool, message: String):
	btn_save.disabled = false
	status_label.text = message
	status_label.modulate = Color.WHITE if success else Color.SALMON

func _on_load_finished(success: bool, message: String):
	load_status_label.text = message
	load_status_label.modulate = Color.WHITE if success else Color.SALMON
	if success:
		SignalBus.request_toggle_menu.emit()
	else:
		_update_action_buttons()

# --- LOAD MENU LOGIC ---

func _refresh_file_list():
	print("🔄 UI: Refreshing File List...")
	
	# 1. Find the container explicitly by name
	var container = find_child("FileList", true, false)
	
	# Fallback if specific name fails: Look for any VBox in the ScrollContainer
	if not container and scroll_container:
		for child in scroll_container.get_children():
			if child is VBoxContainer:
				container = child
				break
	
	if not container:
		print("❌ UI ERROR: Could not find the file list container!")
		return

	# 2. Clear existing list
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	
	selected_file_name = ""
	_update_action_buttons()

	# 3. Read Directory
	# Ensure the path ends with a slash
	var search_path = save_folder_path
	if not search_path.ends_with("/"): search_path += "/"

	var dir = DirAccess.open(search_path)
	if dir == null:
		load_status_label.text = "Could not access saved builds."
		return
	var files: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".json"): files.append(file_name)
	files.sort()
	files.reverse()
	for file_name in files:
		_create_file_item(container, file_name)
	load_status_label.text = "Choose a saved build." if not files.is_empty() else "No saved builds yet."

func _create_file_item(container: VBoxContainer, f_name: String):
	var btn = Button.new()
	btn.text = f_name.trim_suffix(".json")
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.toggle_mode = true
	btn.custom_minimum_size.y = 68
	btn.add_theme_font_size_override("font_size", 30)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.pressed.connect(func(): _on_file_clicked(container, btn, f_name))
	container.add_child(btn)

func _on_file_clicked(container: Node, clicked_btn: Button, f_name: String):
	for child in container.get_children():
		if child is Button and child != clicked_btn:
			child.set_pressed_no_signal(false)
	
	clicked_btn.set_pressed_no_signal(true)
	selected_file_name = f_name
	_update_action_buttons()

func _update_action_buttons():
	var has_selection = (selected_file_name != "")
	if btn_load_confirm: btn_load_confirm.disabled = not has_selection
	if btn_delete: btn_delete.disabled = not has_selection

func _on_load_confirm_pressed():
	if selected_file_name == "": return
	btn_load_confirm.disabled = true
	SignalBus.request_load_game.emit(selected_file_name)

func _on_delete_pressed():
	if selected_file_name == "": return
	var dir = DirAccess.open(save_folder_path)
	if dir:
		dir.remove(selected_file_name)
		_refresh_file_list()

func _build_settings():
	var main = find_child("MainMenu",true,false)
	for button in [btn_export,btn_save,btn_to_load_screen]:
		button.custom_minimum_size.y=100
		button.add_theme_font_size_override("font_size",42)
	main.get_node("Label").add_theme_font_size_override("font_size",56)
	var settings := Button.new()
	settings.text="Settings"
	settings.custom_minimum_size.y=58
	settings.add_theme_font_size_override("font_size",32)
	main.add_child(settings)
	advanced_button=Button.new()
	advanced_button.text="Return to CAD"
	advanced_button.custom_minimum_size.y=68
	advanced_button.add_theme_font_size_override("font_size",34)
	advanced_button.visible=false
	advanced_button.pressed.connect(func():
		var workbench=get_tree().get_first_node_in_group("cad_workbench")
		if workbench: workbench.open_panel())
	main.add_child(advanced_button)
	settings_panel=PanelContainer.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(settings_panel)
	var box:=VBoxContainer.new()
	box.alignment=BoxContainer.ALIGNMENT_CENTER
	settings_panel.add_child(box)
	var label:=Label.new()
	label.text="Settings"
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",56)
	box.add_child(label)
	legacy_toggle=CheckButton.new()
	legacy_toggle.text="Legacy block mode"
	legacy_toggle.add_theme_font_size_override("font_size",40)
	legacy_toggle.custom_minimum_size.y=120
	box.add_child(legacy_toggle)
	legacy_toggle.toggled.connect(func(value):
		var workbench=get_tree().get_first_node_in_group("cad_workbench")
		if workbench:
			workbench.set_enabled(not value)
			if not value: workbench.open_panel()
		_sync_advanced_mode())
	var back:=Button.new()
	back.text="Back"
	back.custom_minimum_size.y=100
	back.add_theme_font_size_override("font_size",40)
	box.add_child(back)
	back.pressed.connect(_show_main_menu)
	settings.pressed.connect(func(): main.visible=false; settings_panel.visible=true; _sync_advanced_mode())
	settings_panel.visible=false

func _sync_advanced_mode():
	var workbench=get_tree().get_first_node_in_group("cad_workbench")
	if advanced_button: advanced_button.visible=workbench!=null and workbench.enabled
	if legacy_toggle: legacy_toggle.set_pressed_no_signal(workbench!=null and not workbench.enabled)
	if btn_export: btn_export.text="Export STL · mm" if workbench!=null and (workbench.enabled or not workbench.document.bodies.is_empty() or not workbench.document.reference_plane.is_empty()) else "Export to STL"

func _on_export_finished(success: bool,message: String):
	status_label.text=message
	status_label.modulate=Color.WHITE if success else Color.SALMON
