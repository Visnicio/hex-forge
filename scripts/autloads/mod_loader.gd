extends Node

# follow same structure as TilesetPickerModal.tilesets
var mod_tilesets: Dictionary[String, MapTilesetConfiguration] = {}

func _ready() -> void:
	load_tilesets_mods()
	
	
func load_tilesets_mods() -> void:
	var user_mods_dir: String = "user://tilesets"
	var dir = DirAccess.open("user://tilesets")
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "": # while theres a file
		if !file_name.begins_with(".") and !file_name.ends_with(".import") and !file_name.ends_with(".md"): # if not a random import
			var full_path = user_mods_dir + "/" + file_name
			
			# the modder needs to make sure that the pck has the same name as the root folder of the mod because of this
			# when loading a pck at runtime it loads its contents to res://, for example res://mod_example/everything-from-root-folder
			# so we use this to find the correct mod directory to load its modinfo
			var mod_pck_name: String = file_name.get_basename()
			
			# Remove .remap extension if present
			if full_path.ends_with(".remap"):
				full_path = full_path.substr(0, full_path.length() - 6)
				
			var success = ProjectSettings.load_resource_pack(full_path)
			if success:
				var mod_info = load("res://" + mod_pck_name + "/mod_info.tres") as ModInfoResource
				print("ModLoader - Read mod succesfully: ", mod_info)
				mod_tilesets[mod_pck_name] = mod_info.mod_configuration
			else:
				print_debug("ModLoader - failed to load mod: ", mod_pck_name)

		file_name = dir.get_next()
	dir.list_dir_end()
