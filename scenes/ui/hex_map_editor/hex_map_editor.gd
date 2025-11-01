class_name HexMapEditor
extends Node2D

enum MapLayer {
	WORLD,
	DECAL
}

@export var tileset_picker_button: Button
@export var tileset_picker: FileDialog
@export var tiles_grid_container: GridContainer
@export var tools_container: Control
@export var map_name_input: LineEdit

@export var main_background: ColorRect
@export var camera: Camera2D

@export var main_panels: Array[MarginContainer] 

@export_group("Tilemaps")
@export var world_tilemap: TileMapLayer
@export var decals_tilemap: TileMapLayer
@export var pencil_tilemap: TileMapLayer

@export_group("Layers")
@export var world_layer_checkbox: CheckBox
@export var decals_layer_checkbox: CheckBox

@export_group("UI")
@export var main_canvas: CanvasLayer


## Holds the coords for the current selected tile to query it on the tileset, set it to (-1,-1) to clear the pencil
var current_selected_tile_coords: Vector2i = Vector2i(-1, -1)

var current_layer_selected: MapLayer = MapLayer.WORLD

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tileset_picker_button.pressed.connect(_on_tileset_picker_button_pressed)
	tileset_picker.file_selected.connect(_on_tileset_selected)
	
	world_layer_checkbox.pressed.connect(_on_world_layer_check_pressed)
	decals_layer_checkbox.pressed.connect(_on_decal_layer_check_pressed)
	
	# clear defaults
	clear_maps()

func _process(delta: float) -> void:
	main_background.global_position = camera.get_screen_center_position() - main_background.get_rect().size / 2 # hacky to keep the background on screen but behind canvas layer
	
	pencil_tilemap.clear()
	if current_selected_tile_coords != Vector2i(-1, -1):
		pencil_tilemap.set_cell(pencil_tilemap.local_to_map(get_global_mouse_position()), 0, current_selected_tile_coords)

func _input(event: InputEvent) -> void:
	
	# Paint the map
	var is_typing_name: bool = map_name_input.get_global_rect().has_point(get_viewport().get_mouse_position())
	var is_something_selected: bool = current_selected_tile_coords != Vector2i(-1, -1)
	if Input.is_action_pressed("left_click") and is_something_selected and !is_mouse_on_tools() and !is_typing_name:
		if current_layer_selected == MapLayer.WORLD:
			world_tilemap.set_cell(world_tilemap.local_to_map(get_global_mouse_position()), 0, current_selected_tile_coords)
		else:
			decals_tilemap.set_cell(decals_tilemap.local_to_map(get_global_mouse_position()), 0, current_selected_tile_coords)
	
	# erase the world
	if Input.is_action_pressed("right_click") and current_selected_tile_coords != Vector2i(-1, -1):
		if current_layer_selected == MapLayer.WORLD:
			world_tilemap.set_cell(world_tilemap.local_to_map(get_global_mouse_position()), 0, Vector2i(-1, -1))
		else:
			decals_tilemap.set_cell(decals_tilemap.local_to_map(get_global_mouse_position()), 0, Vector2i(-1, -1))

	if Input.is_action_just_pressed("hide_ui"):
		main_canvas.visible = !main_canvas.visible

func _on_tileset_picker_button_pressed() -> void:
	tileset_picker.show()


func _on_tileset_selected(selected_file_path: String) -> void:
	load_tileset_for_map(selected_file_path)


func _create_tile_button(button_texture: Texture2D, buttons_container: GridContainer, original_tile_coords: Vector2i) -> void:
	var new_button: TextureButton = TextureButton.new()
	new_button.texture_normal = button_texture
	
	new_button.pressed.connect(func():
		current_selected_tile_coords = original_tile_coords
		)
	
	buttons_container.add_child(new_button)


func load_tileset_for_map(tileset_resource_path: String) -> void:
	# load the tileset
	var loaded_tileset: TileSet = load(tileset_resource_path)
	pencil_tilemap.tile_set = loaded_tileset
	world_tilemap.tile_set = loaded_tileset
	decals_tilemap.tile_set = loaded_tileset
	
	#get its source
	var tileset_source: TileSetSource = loaded_tileset.get_source(0)
	
	var rows: int = tileset_source.get_atlas_grid_size().y
	# but it is 1-indexed, so I need to subtract -1 to query i coords
	var cols: int = tileset_source.get_atlas_grid_size().x
	
	if tileset_source is TileSetAtlasSource: # if selected is a source
		for row in rows:
			for col in cols:
				var tile_coord: Vector2i = Vector2i(col, row)
				
				# for each tile in tileset, check if its set to usable
				if !tileset_source.has_tile(tile_coord): continue
				
				# creates a new atlas to hold the tile texture
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = tileset_source.texture
				atlas.region = tileset_source.get_tile_texture_region(tile_coord)
				
				# creates the button
				_create_tile_button(atlas, tiles_grid_container, tile_coord)


func clear_maps() -> void:
	world_tilemap.clear()
	world_tilemap.tile_set = null
	pencil_tilemap.clear()
	pencil_tilemap.tile_set = null
	decals_tilemap.clear()
	decals_tilemap.tile_set = null


func _on_world_layer_check_pressed() -> void:
	current_layer_selected = MapLayer.WORLD
	decals_layer_checkbox.button_pressed = false

func _on_decal_layer_check_pressed() -> void:
	current_layer_selected = MapLayer.DECAL
	world_layer_checkbox.button_pressed = false


func is_mouse_on_tools() -> bool:
	
	for panel: MarginContainer in main_panels:
		if panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
			return true
	
	return false
