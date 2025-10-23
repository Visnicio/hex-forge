extends Node

@export var target_camera: Camera2D

@export var camera_speed: float = 100

func _physics_process(delta: float) -> void:
	var camera_pan_direction: Vector2 = Vector2.ZERO
	
	camera_pan_direction.x = Input.get_axis("camera_pan_left", "camera_pan_right")
	camera_pan_direction.y = Input.get_axis("camera_pan_up", "camera_pan_down")
	
	target_camera.global_position += camera_pan_direction * camera_speed * delta
	
func _input(event: InputEvent) -> void:
	const up = 4
	const down = 5
	if event is InputEventMouseButton:
		if event.button_index == up:
			target_camera.zoom += Vector2(0.1, 0.1)
		if event.button_index == down:
			target_camera.zoom -= Vector2(0.1, 0.1)
