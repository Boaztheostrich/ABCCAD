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
	print("UI: Requesting Save")
	SignalBus.request_save_game.emit("") 
	if btn_save:
		var original_text = btn_save.text
		btn_save.text = "Saved!"
		await get_tree().create_timer(1.0).timeout
		btn_save.text = original_text

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
		child.queue_free()
	
	selected_file_name = ""
	_update_action_buttons()

	# 3. Read Directory
	# Ensure the path ends with a slash
	var search_path = save_folder_path
	if not search_path.ends_with("/"): search_path += "/"

	var dir = DirAccess.open(search_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var found_count = 0
		
		while file_name != "":
			# Skip directories (folders) and ensure it is a JSON file
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				print("   📄 Found file: ", file_name)
				_create_file_item(container, file_name)
				found_count += 1
			
			file_name = dir.get_next()
		
		if found_count == 0:
			print("⚠️ UI: No .json files found in ", search_path)
			
			# OPTIONAL: Add a "No saves found" label so the user knows it's not broken
			var label = Label.new()
			label.text = "No saved games found."
			container.add_child(label)
			
	else:
		print("❌ UI ERROR: Could not access folder: ", search_path)

func _create_file_item(container: VBoxContainer, f_name: String):
	var btn = Button.new()
	btn.text = f_name
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.toggle_mode = true
	btn.custom_minimum_size.y = 40 
	btn.pressed.connect(func(): _on_file_clicked(container, btn, f_name))
	container.add_child(btn)

func _on_file_clicked(container: Node, clicked_btn: Button, f_name: String):
	for child in container.get_children():
		if child is Button and child != clicked_btn:
			child.set_pressed_no_signal(false)
	
	selected_file_name = f_name
	_update_action_buttons()

func _update_action_buttons():
	var has_selection = (selected_file_name != "")
	if btn_load_confirm: btn_load_confirm.disabled = not has_selection
	if btn_delete: btn_delete.disabled = not has_selection

func _on_load_confirm_pressed():
	if selected_file_name == "": return
	print("UI: Confirmed Load for ", selected_file_name)
	SignalBus.request_load_game.emit(selected_file_name)
	
	# OLD LINE (Causes desync):
	# _toggle_visibility() 
	
	# NEW LINE (Keeps movement logic in sync):
	SignalBus.request_toggle_menu.emit()

func _on_delete_pressed():
	if selected_file_name == "": return
	var dir = DirAccess.open(save_folder_path)
	if dir:
		dir.remove(selected_file_name)
		_refresh_file_list()
