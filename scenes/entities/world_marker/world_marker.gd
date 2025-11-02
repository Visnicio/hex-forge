class_name WorldMarker extends TextureButton

@export var marker_color: Color:
	set(new_value):
		marker_color = new_value
		modulate = marker_color
		
var marker_name: String = "":
	set(new_value):
		marker_name = new_value
		$MarkerName.text = new_value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	SignalBus.marker_pressed.emit(self)
