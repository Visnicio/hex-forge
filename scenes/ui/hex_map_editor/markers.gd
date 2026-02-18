class_name MarkersManager extends Node

@export var marker_preview_scene: PackedScene
@export var world_marker_scene: PackedScene
@export var editor: HexMapEditor


@export_group("UI")
@export var close_data_container_button: Button
@export var place_poi_button: Button
@export var marker_data_container: MarginContainer
@export var marker_name_input: LineEdit
@export var marker_description_input: TextEdit
@export var marker_color_input: ColorPicker
@export var delete_marker_button: Button

var is_placing: bool = false
var current_preview: Sprite2D = null
var current_selected_marker: WorldMarker = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	place_poi_button.pressed.connect(_on_place_poi_button_pressed)
	marker_name_input.text_changed.connect(_on_marker_name_input_changed)
	marker_color_input.color_changed.connect(_on_marker_color_changed)
	marker_description_input.text_changed.connect(_on_marker_description_changed)
	close_data_container_button.pressed.connect(func():
		marker_data_container.hide()
		)
	delete_marker_button.pressed.connect(func():
		current_selected_marker.queue_free()
		marker_data_container.hide()
		)
	marker_data_container.hide()
	SignalBus.marker_pressed.connect(_on_marker_pressed)
	
func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("left_click") and is_placing:
		var new_world_marker: WorldMarker = world_marker_scene.instantiate() as WorldMarker
		new_world_marker.global_position = current_preview.global_position
		add_child(new_world_marker)
		current_preview.queue_free()
		select_world_marker(new_world_marker)
		is_placing = false
		
	# deselect current placing on esc
	if Input.is_key_pressed(KEY_ESCAPE) and is_placing:
		current_preview.queue_free()
		is_placing = false

func _on_marker_pressed(marker: WorldMarker) -> void:
	select_world_marker(marker)
	marker_data_container.show()

func _on_place_poi_button_pressed() -> void:
	if is_placing: return
	
	editor.deselect_current_pencil()
	var preview: Sprite2D = marker_preview_scene.instantiate()
	add_child(preview)
	current_preview = preview
	is_placing = true


func select_world_marker(world_marker: WorldMarker) -> void:
	current_selected_marker = world_marker
	marker_name_input.text = world_marker.marker_name
	marker_color_input.color = world_marker.marker_color
	marker_description_input.text = world_marker.marker_description
	marker_data_container.show()

func clear_all_markers() -> void:
	for child in get_children():
		child.queue_free()

func _on_marker_name_input_changed(new_text: String) -> void:
	current_selected_marker.marker_name = new_text

func _on_marker_color_changed(new_color: Color) -> void:
	current_selected_marker.marker_color = new_color

func _on_marker_description_changed() -> void:
	current_selected_marker.marker_description = marker_description_input.text
