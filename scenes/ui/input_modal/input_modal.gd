class_name InputModal extends Panel

signal value_changed(new_value: String)

@export var input: LineEdit
@export var confirm_button: Button
@export var modal_title: Label

var current_value: String = ""

func _ready() -> void:
	confirm_button.pressed.connect(func():
		queue_free()
		)
	
	input.grab_focus()
	
	input.text_changed.connect(func(new_text: String):
		current_value = new_text
		value_changed.emit(current_value)
		)
