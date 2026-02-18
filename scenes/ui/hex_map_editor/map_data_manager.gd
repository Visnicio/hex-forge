## Script used to handle saving and loading data from a save file into the editor tiles and other things like markers
## this is here to our SaveManager can exist without the burden of a map editor (a.k.a headless save manager)
class_name MapDataManager extends Node

enum State {
	SAVING,
	LOADING
}

@export var map_file_dialog: FileDialog
@export var new_map_button: Button
@export var save_map_button: Button
@export var load_map_button: Button
@export var export_map_button: Button
@export var map_name_input: LineEdit
@export var main_canvas: CanvasLayer

@export_group("Markers")
@export var markers: MarkersManager
@export var world_marker_scene: PackedScene

var editor: HexMapEditor
var current_state: State = State.LOADING
var last_map_loaded_path: String = ""

func _ready() -> void:
	editor = get_parent() as HexMapEditor
	map_file_dialog.add_filter("*.json", "Map Files")
	
	new_map_button.pressed.connect(_on_new_map_pressed)
	
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

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("shortcut_save"):
		if last_map_loaded_path != "":
			print_debug("Quicksaving: ", last_map_loaded_path)
			current_state = State.SAVING
			map_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			map_file_dialog.show()

## Starts a new map
func _on_new_map_pressed() -> void:
	editor.clear_maps()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	markers.clear_all_markers()
	GlobalEditorData.user_layers.delete_all_layers()
	GlobalEditorData.user_layers.add_base_layers()


func on_file_selected(map_path: String) -> void:
	if current_state == State.SAVING:
		save_current_map(map_path, editor.current_map_tileset_configuration)
		
	elif current_state == State.LOADING:
		load_map_into_editor(map_path);

## Loads a mapa into the editor... hm
func load_map_into_editor(map_path: String) -> void:
	editor.clear_maps()
	markers.clear_all_markers()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	
	var map_data: Dictionary = SaveManager.load_map(map_path)
	map_name_input.text = map_data.get("map_name", "No Name Saved")
	var map_config_data: MapTilesetConfiguration = null
	if map_data.has("map_tileset_configuration"):
		# we save the resource path to we can load it
		map_config_data = load(map_data.get("map_tileset_configuration"))
	editor.current_map_tileset_configuration = map_config_data
	editor.load_tileset_for_map(map_config_data)
	
	_load_sorted_layers(map_data)
	
	GlobalEditorData.user_layers._refresh_layer_visuals()
	
	# load markers
	if map_data.has("markers"):
		for marker_name: String in map_data.markers.keys():
			var new_world_marker = world_marker_scene.instantiate() as WorldMarker
			new_world_marker.global_position = str_to_var("Vector2"+map_data.markers[marker_name].global_position) 
			markers.add_child(new_world_marker)
			new_world_marker.marker_description = map_data.markers[marker_name].marker_description
			new_world_marker.marker_color = str_to_var("Color"+map_data.markers[marker_name].marker_color) 
			new_world_marker.marker_name = map_data.markers[marker_name].marker_name
	
	last_map_loaded_path = map_path

func save_current_map(map_path: String, map_tileset_configuration: MapTilesetConfiguration) -> void:
	var map_data = {}
	map_data.map_name = map_name_input.text
	map_data.markers = _get_markers_to_save()
	map_data.map_tileset_configuration = map_tileset_configuration.resource_path
	map_data.manifest_version = ProjectSettings.get_setting("application/config/version") 
	
	map_data.layers = {}
	
	# Create the .cells  key is cell_coord and value is dictionary
	for layer: UserLayer in GlobalEditorData.user_layers.get_all_layers():
		map_data.layers[layer.layer_name] = {}
		map_data.layers[layer.layer_name].cells = {}
		map_data.layers[layer.layer_name].index = GlobalEditorData.user_layers.get_user_layer_index(layer)
		for cell_coord: Vector2i in layer.layer_tilemap_ref.get_used_cells(): # loop for the used cells to create the cell data to save
			map_data.layers[layer.layer_name].cells[cell_coord] = {
				"atlas_coords": layer.layer_tilemap_ref.get_cell_atlas_coords(cell_coord),
				"source_id": layer.layer_tilemap_ref.get_cell_source_id(cell_coord)
			}
	
	SaveManager.save_map(map_path, map_file_dialog.current_file, map_data)


func _get_markers_to_save() -> Dictionary:
	var result := {}
	
	for child: WorldMarker in markers.get_children():
		if child is WorldMarker:
			var marker_data = {}
			marker_data.global_position = child.global_position
			marker_data.marker_name = child.marker_name
			marker_data.marker_color = child.marker_color
			marker_data.marker_description = child.marker_description
			result[child.name] = marker_data
	return result

## loads the layers from save data sorted by their index (when writing the save data we dont know which order the engine is gonna write to the file)
func _load_sorted_layers(map_data: Dictionary) -> void:
	var sorted_layers_data: Array = [] # Array[Dictionary]
	
	for layer_name: String in map_data.layers:
		var layer_content = map_data.layers[layer_name]
		layer_content["_temp_name_ref"] = layer_name 
		sorted_layers_data.append(layer_content)

	sorted_layers_data.sort_custom(func(a, b):
		return a.get("index", 0) < b.get("index", 0)
	)

	for layer_data: Dictionary in sorted_layers_data:
		var layer_name = layer_data["_temp_name_ref"]
		
		GlobalEditorData.user_layers.add_new_layer(layer_name)
		
		var new_layer_index = GlobalEditorData.user_layers.all_user_layers.size() - 1
		var new_layer = GlobalEditorData.user_layers.all_user_layers[new_layer_index]
		
		if layer_data.has("cells"):
			var cells = layer_data.cells
			for cell_data_key: String in cells.keys():
				var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
				var cell_content: Dictionary = cells[cell_data_key]
				
				var source_id: int = 0
				if cell_content.has("source_id"): 
					source_id = cell_content.get("source_id")
				
				var atlas_coords = str_to_var("Vector2i"+str(cell_content.get("atlas_coords", "(0,0)")))
				
				new_layer.layer_tilemap_ref.set_cell(key_as_vector, source_id, atlas_coords)
