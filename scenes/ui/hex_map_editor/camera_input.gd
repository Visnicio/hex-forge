class_name CameraInput extends Node

@export var editor: HexMapEditor
@export var target_camera: Camera2D
@export var camera_speed: float = 100
@export var main_canvas: CanvasLayer
@export var panning_camera_speed: float = 20

var ui_has_focus: bool = false
var _is_panning: bool = false

func _ready() -> void:
	#for child in main_canvas.get_children():
		#connect_focus_signal_from_node(child)
	pass

func _physics_process(delta: float) -> void:
	var camera_pan_direction: Vector2 = Vector2.ZERO
	
	if !ui_has_focus:
		camera_pan_direction.x = Input.get_axis("camera_pan_left", "camera_pan_right")
		camera_pan_direction.y = Input.get_axis("camera_pan_up", "camera_pan_down")
	
	if Input.is_action_pressed("camera_rush"):
		camera_speed = 400
	else:
		camera_speed = 200
		
	#var current_speed = camera_speed * (1.0 / target_camera.zoom.x)
	target_camera.global_position += camera_pan_direction * camera_speed * delta
	
	ui_has_focus = get_viewport().gui_get_focus_owner() != null
	
func _unhandled_input(event: InputEvent) -> void:
	_handle_camera_zoom_on_unhandled_input(event)
	_handle_mouse_panning_on_unhandled_input(event)


func connect_focus_signal_from_node(node: Control) -> void:
	for child in node.get_children():
		if child is LineEdit or child is TextEdit:
			child.focus_entered.connect(func():
				ui_has_focus = true
				)
			child.focus_exited.connect(func():
				ui_has_focus = false
				)
		if child is Control:
			connect_focus_signal_from_node(child)


func _handle_camera_zoom_on_unhandled_input(event: InputEvent) -> void:
	const WHEEL_UP = 4
	const WHEEL_DOWN = 5
	
	if event is InputEventMouseButton and event.pressed and !editor.is_mouse_on_tools():
		if event.button_index == WHEEL_UP:
			# Aproxima (zoom in)
			target_camera.zoom += Vector2(0.1, 0.1)
		elif event.button_index == WHEEL_DOWN:
			# Afasta (zoom out)
			target_camera.zoom -= Vector2(0.1, 0.1)

		# Limita o zoom entre 0.5x e 2x
		target_camera.zoom = target_camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2, 2))

func _handle_mouse_panning_on_unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = event.pressed
	elif event is InputEventMouseMotion and _is_panning:
		target_camera.position -= event.relative / target_camera.zoom
	