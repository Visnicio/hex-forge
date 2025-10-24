extends Node

enum State {
	SAVING,
	LOADING
}

@export var map_file_dialog: FileDialog
@export var save_map_button: Button
@export var load_map_button: Button
@export var map_name_input: LineEdit

var editor: HexMapEditor

var current_state: State = State.LOADING

func _ready() -> void:
	editor = get_parent() as HexMapEditor
	
	load_map_button.pressed.connect(func():
		current_state = State.LOADING
		map_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		map_file_dialog.show()
		)
	
	save_map_button.pressed.connect(func():
		current_state = State.SAVING
		map_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		map_file_dialog.show()
		)
	
	map_file_dialog.file_selected.connect(on_file_selected)

	
func on_file_selected(map_path: String) -> void:
	if current_state == State.SAVING:
		print(map_path)
		print("trying to save ", map_name_input.text, " on path ", map_path)
		
		var map_data = {}
		map_data.cells = {}
		
		# Create the .cells  key is cell_coord and value is dictionary
		for cell_coord: Vector2i in editor.world_tilemap.get_used_cells(): # loop for the used cells to create the cell data to save
			map_data.cells[cell_coord] = {
				"atlas_coords": editor.world_tilemap.get_cell_atlas_coords(cell_coord)
			}
		
		map_data.map_name = map_name_input.text
		
		SaveManager.save_map(map_path, map_file_dialog.current_file, map_data)
		
	elif current_state == State.LOADING:
		var map_data: Dictionary = SaveManager.load_map(map_path)
		map_name_input.text = map_data.get("map_name", "No Name Saved")
		
		for cell_data_key: String in map_data.cells.keys():
			var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
			var cell_data: Dictionary = map_data.cells[cell_data_key]
			editor.world_tilemap.set_cell(key_as_vector, 0, str_to_var("Vector2i"+cell_data.atlas_coords))
