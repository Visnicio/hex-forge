class_name Utils extends Node

static func get_json_data(json_path: String) -> Dictionary:
	var file_access = FileAccess.open(json_path, FileAccess.READ)
	if file_access == null:
		printerr("Error while trying to open file ", json_path)
		print_stack()
		return {"error": "error"}
	var json_text = file_access.get_as_text()
	file_access.close()
	
	var json = JSON.new()
	var result = json.parse(json_text)
	if result == OK:
		var data = json.data
		print("Loaded JSON from util ", json.data)
		return json.data
	else:
		push_error("Error parsing save file JSON")
		
	return {}
