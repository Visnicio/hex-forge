class_name Utils extends Node

static var MODAL_SCENE = preload("res://scenes/ui/input_modal/input_modal.tscn")

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


static func input_modal(modal_title: String, where_to_add: Node, old_value: String = "") -> InputModal:
	var new_modal: InputModal = MODAL_SCENE.instantiate() as InputModal
	new_modal.modal_title.text = modal_title
	if !old_value.is_empty():
		new_modal.current_value = old_value
		new_modal.input.text = old_value
	where_to_add.add_child(new_modal)
	return new_modal
