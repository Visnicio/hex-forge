extends Panel


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide()
	$Close.pressed.connect(func():
		hide()
		)
	$VBoxContainer/Version.text = "\n\nVersion: " +  ProjectSettings.get_setting("application/config/version") 
