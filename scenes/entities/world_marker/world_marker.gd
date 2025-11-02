class_name WorldMarker extends TextureButton

@export var marker_color: Color:
	set(new_value):
		marker_color = new_value
		modulate = marker_color
		
var marker_name: String = "":
	set(new_value):
		marker_name = new_value
		name = new_value
		$MarkerName.text = new_value
		
var marker_description: String = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	SignalBus.marker_pressed.emit(self)


func _draw() -> void:
	draw_circle(global_position, 2, Color.RED, true, 2)
