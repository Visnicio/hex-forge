## A autload used to store global variables to avoid Dependecy INjenction hell
extends Node

enum CursorMode {
	NOTHING_SELECTED,
	PAINTING_TILES,
}

const NOTHING_SELECTED_CURSOR_SPRITE: Texture2D = preload("res://assets/gfx/ui/kenney_cursor-pack/PNG/Outline/Default/cursor_none.png")
const PAINTING_TILES_CURSOR_SPRITE: Texture2D = preload("res://assets/gfx/ui/kenney_cursor-pack/PNG/Outline/Default/drawing_brush.png")
const POINTING_CURSOR_SPRITE: Texture2D = preload("res://assets/gfx/ui/kenney_cursor-pack/PNG/Outline/Default/hand_point.png")

var map_editor_ref: HexMapEditor
var layers_tilemaps_holder: Node2D
var user_layers: UserLayers
var main_canvas: CanvasLayer

var selected_map_config: MapTilesetConfiguration = null

func _ready() -> void:
	# Changes only the arrow shape of the cursor.
	# This is similar to changing it in the project settings.
	Input.set_custom_mouse_cursor(NOTHING_SELECTED_CURSOR_SPRITE, Input.CURSOR_ARROW)

	# for drawing we use the cross cursor
	Input.set_custom_mouse_cursor(PAINTING_TILES_CURSOR_SPRITE, Input.CURSOR_CROSS)
	
	Input.set_custom_mouse_cursor(POINTING_CURSOR_SPRITE, Input.CURSOR_POINTING_HAND)

# generally we should avoid putting logic here to keep the app event driven and light on the CPU side
# but sometimes things needs to be constantly checked, so go wild
func _physics_process(_delta: float) -> void:
	_sync_tileset_data_between_layers()

	# Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	
func _sync_tileset_data_between_layers() -> void:
	if map_editor_ref == null: return
	if map_editor_ref.current_tileset == null: return
	if user_layers == null: return
	
	for layer: UserLayer in user_layers.get_all_layers():
		layer.layer_tilemap_ref.tile_set = map_editor_ref.current_tileset
		# bad practice again, it makes the code dependent on the pencil tilemap but it is what it is
		# TODO - HexMapEditor._update_tilesets_scales could be a solution but its 2am and im tired
		layer.layer_tilemap_ref.scale = map_editor_ref.pencil_tilemap.scale