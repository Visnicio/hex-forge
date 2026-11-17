class_name WorldMarker extends Sprite2D

const DEFAULT_MARKER_SCALE: Vector2 = Vector2(0.017, 0.018)

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

var is_dragging: bool = false
@export var start_dragging_timer: Timer # kinda of a coyote timer, so it doenst start getting dragged any click

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Button.pressed.connect(_on_pressed)
	$Button.button_down.connect(func():
		start_dragging_timer.start()
		)
		
	$Button.button_up.connect(func():
		if !start_dragging_timer.is_stopped():
			start_dragging_timer.stop()
		else:
			is_dragging = false
		)
		
	start_dragging_timer.timeout.connect(func():
		is_dragging = true
		)

func _on_pressed() -> void:
	if is_dragging: return # if its dragging, doesnt open the panel when mouse up
	SignalBus.marker_pressed.emit(self)


func _draw() -> void:
	draw_circle(global_position, 2, Color.RED, true, 2)

func _physics_process(delta: float) -> void:
	if is_dragging:
		global_position = get_global_mouse_position()
