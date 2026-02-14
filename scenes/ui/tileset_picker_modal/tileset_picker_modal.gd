## This node is responsible for handling tilesets and maps for the mapping tool.
## It reads from first-party tilesets already preconfigured in the res:// folder but also
## reads custom tilesets configs from user://
class_name TileSetPickerModal extends Control

## Use new_tileset to query on TileSetPickerModal.tilesets keys
signal config_changed(new_tileset: String)
var tilesets: Dictionary[String, Dictionary] = {}

@export var tileset_picker: OptionButton

func _ready() -> void:
	hide()
	load_first_party_tilesets()
	tileset_picker.add_item("None")
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


func load_first_party_tilesets() -> void:
	var tilesets_dir: String = "res://resources/definitions/tilesets"
	var dir = DirAccess.open(tilesets_dir)
	if not dir:
		push_error("Could not find tilesets dir")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "": # while theres a file
		if !file_name.begins_with(".") and !file_name.ends_with(".import") and !file_name.ends_with(".md"): # if not a random import
			var full_path = tilesets_dir + "/" + file_name
			
			# Remove .remap extension if present
			if full_path.ends_with(".remap"):
				full_path = full_path.substr(0, full_path.length() - 6)
			
			var file_access = FileAccess.open(full_path, FileAccess.READ)
			if file_access == null:
				printerr("Error while trying to open file ", full_path)
				print_stack()
				return
			var json_text = file_access.get_as_text()
			file_access.close()
			
			var json = JSON.new()
			var result = json.parse(json_text)
			if result == OK:
				var data = json.data
				print("Loaded ", json.data.title)
				tilesets[data.title] = {
					"tileset_resource": data.tileset_resource,
					"tilemap_scale": data.tilemap_scale,
					"file_name": file_name,
					"file_path": full_path
				}
			else:
				push_error("Error parsing save file JSON: ", file_name)
				#return {}

		file_name = dir.get_next()
	dir.list_dir_end()
	
