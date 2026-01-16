## This node is responsible for handling tilesets and maps for the mapping tool.
## It reads from first-party tilesets already preconfigured in the res:// folder but also
## reads custom tilesets configs from user://
class_name TileSetPickerModal extends Control

signal config_changed
var tilesets: Dictionary[String, Dictionary] = {}

@export var tileset_picker: OptionButton

func _ready() -> void:
	load_first_party_tilesets()
	
	for tileset_name in tilesets.keys():
		tileset_picker.add_item(tileset_name)


func load_first_party_tilesets() -> void:
	var items: Array[Resource] = []
	
	var tilesets_dir: String = "res://resources/tilesets"
	var dir = DirAccess.open(tilesets_dir)
	if not dir:
		push_error("Could not find tilesets dir")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "": # while theres a file
		if !file_name.begins_with(".") and !file_name.ends_with(".import"): # if not a random import
			var full_path = tilesets_dir + "/" + file_name
			
			# Remove .remap extension if present
			if full_path.ends_with(".remap"):
				full_path = full_path.substr(0, full_path.length() - 6)

			if ResourceLoader.exists(full_path):
				var res = ResourceLoader.load(full_path)
				if res:
					items.append(res)
				else:
					push_error("Failed to load resource: ", full_path)
			else:
				push_error("Resource does not exist: ", full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	for resource: Resource in items:
		if resource is TileSet:
			tilesets[resource.resource_name] = {
				"resource": resource,
				"path": resource.resource_path
			}
