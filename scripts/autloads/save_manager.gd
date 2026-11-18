extends Node


var data: Dictionary = {}


func save_map(map_save_path: String, _map_name: String, map_data: Dictionary) -> bool:
	var file = FileAccess.open(map_save_path, FileAccess.WRITE)
	if file:
		var json_text = JSON.stringify(map_data, "\t") # parses the data to json "\t" for indentation
		file.store_string(json_text) # store json in file
		file.close() # close
		print("map saved at: ", map_save_path)
		return true
	else:
		push_error("Couldnt open save file")
	
	return false


## Loads a map file and return its contents as raw dictionary, without parsing to [code]MapData[/code]
func load_map(map_path: String) -> Dictionary:
	if not FileAccess.file_exists(map_path):
		print("No map file found")
		return {}  # Return empty if theres no save

	var file = FileAccess.open(map_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var result = json.parse(json_text)
	if result == OK:
		return json.data
	else:
		push_error("Error parsing save file JSON")
		return {}
