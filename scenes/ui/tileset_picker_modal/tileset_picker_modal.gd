## This node is responsible for handling tilesets and maps for the mapping tool.
## It reads from first-party tilesets already preconfigured in the res:// folder but also
## reads custom tilesets configs from user://
class_name TileSetPickerModal extends Control

## Use new_tileset to query on TileSetPickerModal.tilesets keys
signal config_changed(new_tileset_title: String)

## Holds every selectable tileset, key is tileset id (must be unique) and value is config
var tilesets: Dictionary[String, MapTilesetConfiguration] = {}

@export var tileset_picker: OptionButton

func _ready() -> void:
	hide()
	load_samples_tilesets()
	get_mods_tilesets()
	tileset_picker.add_item("None")
	
	# populates selectable tilesets
	for tileset_name in tilesets.keys():
		tileset_picker.add_item(tileset_name)
		
	tileset_picker.item_selected.connect(func(index: int):
		var selected_title = tileset_picker.get_item_text(index)
		if tilesets.has(selected_title):
			config_changed.emit(selected_title)
		else:
			config_changed.emit("None")
		hide()
	)
	
	$Close.pressed.connect(func():
		hide()
		)


func load_samples_tilesets() -> void:
	var tilesets_dir: String = "res://samples"
	var dir = DirAccess.open(tilesets_dir)
	if not dir:
		push_error("Could not find sample tilesets dir")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "": # while theres a file
		if !file_name.begins_with(".") and !file_name.ends_with(".import") and !file_name.ends_with(".md"): # if not a random import
			var full_path = tilesets_dir + "/" + file_name
			
			# Remove .remap extension if present
			if full_path.ends_with(".remap"):
				full_path = full_path.substr(0, full_path.length() - 6)
			
			var loaded_config: MapTilesetConfiguration = load(full_path)
			if loaded_config != null:
				tilesets[loaded_config.tileset_name] = loaded_config
			else:
				push_error("Error parsing save file JSON: ", file_name)

		file_name = dir.get_next()
	dir.list_dir_end()

func get_mods_tilesets() -> void:
	tilesets.merge(ModLoader.mod_tilesets)
	print_debug(tilesets)
