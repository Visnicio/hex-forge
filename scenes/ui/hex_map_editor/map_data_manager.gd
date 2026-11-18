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

## Loads a map into the editor, replacing whatever is currently loaded
func load_map_into_editor(map_path: String) -> void:
	editor.clear_maps()
	markers.clear_all_markers()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	
	var map_data: MapData = MapData.from_dict(SaveManager.load_map(map_path))
	
	map_name_input.text = map_data.map_name
	
	editor.current_map_tileset_configuration = map_data.map_tileset_configuration
	if map_data.map_tileset_configuration:
		editor.load_tileset_for_map(map_data.map_tileset_configuration)
	
	_load_sorted_layers(map_data)
	
	GlobalEditorData.user_layers._refresh_layer_visuals()
	
	_load_markers(map_data)
	
	last_map_loaded_path = map_path


## Main function that creates the map data and saving in the json
func save_current_map(map_path: String, map_tileset_configuration: MapTilesetConfiguration) -> void:
	var map_data: MapData  = MapData.new()
	map_data.map_name = map_name_input.text
	map_data.markers = _get_markers_to_save()
	map_data.layers = _get_layers_to_save()
	map_data.map_tileset_configuration = map_tileset_configuration
	map_data.manifest_version = ProjectSettings.get_setting("application/config/version") 
	SaveManager.save_map(map_path, map_file_dialog.current_file, MapData.to_dict(map_data))


func _get_markers_to_save() -> Dictionary[StringName, MarkerData]:
	var result: Dictionary[StringName, MarkerData] = {}
	
	for child: WorldMarker in markers.get_children():
		if child is WorldMarker:
			var marker_data: MarkerData = MarkerData.new()
			marker_data.global_position = child.global_position
			marker_data.marker_name = child.marker_name
			marker_data.marker_color = child.marker_color
			marker_data.marker_description = child.marker_description
			marker_data.marker_scale = child.scale
			
			result[child.name] = marker_data
	return result


func _get_layers_to_save() -> Dictionary[StringName, LayerData]:
	var result_layers: Dictionary[StringName, LayerData] = {}
	
	# Create the .cells  key is cell_coord and value is dictionary
	for layer: UserLayer in GlobalEditorData.user_layers.get_all_layers():
		result_layers[layer.layer_name] = LayerData.new()
		result_layers[layer.layer_name].cells = {}
		result_layers[layer.layer_name].index = GlobalEditorData.user_layers.get_user_layer_index(layer)
		for cell_coord: Vector2i in layer.layer_tilemap_ref.get_used_cells(): # loop for the used cells to create the cell data to save
			result_layers[layer.layer_name].cells[cell_coord] = {
				"atlas_coords": layer.layer_tilemap_ref.get_cell_atlas_coords(cell_coord),
				"source_id": layer.layer_tilemap_ref.get_cell_source_id(cell_coord)
			}
			
	return result_layers

## loads the layers from save data sorted by their index (when writing the save data we dont know which order the engine is gonna write to the file)
func _load_sorted_layers(map_data: MapData) -> void:
	var sorted_layer_names: Array = map_data.layers.keys()
	sorted_layer_names.sort_custom(func(a: StringName, b: StringName):
		return map_data.layers[a].index < map_data.layers[b].index
	)

	for layer_name: StringName in sorted_layer_names:
		var layer_data: LayerData = map_data.layers[layer_name]
		var new_layer: UserLayer = GlobalEditorData.user_layers.add_new_layer(layer_name)
		
		for cell_coord: Vector2i in layer_data.cells.keys():
			var cell_content: Dictionary = layer_data.cells[cell_coord]
			new_layer.layer_tilemap_ref.set_cell(cell_coord, cell_content.source_id, cell_content.atlas_coords)


## Instantiates the world markers from save data
func _load_markers(map_data: MapData) -> void:
	for marker_data: MarkerData in map_data.markers.values():
		var new_world_marker: WorldMarker = world_marker_scene.instantiate() as WorldMarker
		new_world_marker.global_position = marker_data.global_position
		markers.add_child(new_world_marker)
		new_world_marker.marker_description = marker_data.marker_description
		new_world_marker.marker_color = marker_data.marker_color
		new_world_marker.marker_name = marker_data.marker_name
		new_world_marker.scale = marker_data.marker_scale
