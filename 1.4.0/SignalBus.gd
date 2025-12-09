extends Node

# These are the "events" or "messages" your game can send
# Events
signal request_export_stl
signal request_save_game(filename: String) # Accepts optional filename
signal request_load_game(filename: String) # Accepts filename to load
signal request_toggle_menu(menu_name: String)
signal block_type_changed(current_index: int)

# NEW: Used by SaveSystem to tell the Main Game to spawn a block
# Old line:
# signal request_rebuild_block(grid_pos: Vector3i, shape_type: String, rotation: Basis, color: Color)

# NEW line (Add 'exact_pos'):
signal request_rebuild_block(grid_pos: Vector3i, shape_type: String, rotation: Basis, color: Color, exact_pos: Vector3)
func _ready():
	print("🚌 SIGNAL BUS: I am ready and listening for traffic.")
