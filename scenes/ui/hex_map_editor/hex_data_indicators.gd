## Draws a small badge on every hex that has data (name, notes or a color), so the user can see where they wrote things.[br]
## Each badge uses the color of its hex, so it also works to group hexes (political map, regions, whatever the user wants).[br]
## It draws in the same space as the tilemaps (copies the pencil tilemap scale), so the badge
## grows and shrinks together with the hexes, no matter the tileset size or camera zoom
class_name HexDataIndicators extends Node2D

## Every layer shares the pencil tileset and scale, so its used to convert tile coords to positions
@export var reference_tilemap: TileMapLayer
@export var hex_data_store: HexDataStore
## Button that shows/hides the badges
@export var toggle_button: BaseButton

@export var outline_color: Color = Color(0.055, 0.067, 0.13)
## Badge radius relative to the smallest side of the tile
@export_range(0.02, 0.5) var badge_radius_ratio: float = 0.12
## How far above the hex center the badge sits, relative to the tile height (0 = center)
@export_range(0.0, 0.5) var badge_vertical_offset_ratio: float = 0.22

var _last_tileset: TileSet
var _last_scale: Vector2


func _ready() -> void:
	hex_data_store.hex_changed.connect(func(_coord: Vector2i): queue_redraw())
	hex_data_store.store_reset.connect(queue_redraw)

	visible = toggle_button.button_pressed
	toggle_button.toggled.connect(func(toggled_on: bool): visible = toggled_on)


# the tileset/scale change when the user picks another tileset or loads a map, theres no signal for it,
# so its checked here and only redraws when it actually changed
func _process(_delta: float) -> void:
	if reference_tilemap.tile_set != _last_tileset or reference_tilemap.scale != _last_scale:
		_last_tileset = reference_tilemap.tile_set
		_last_scale = reference_tilemap.scale
		global_transform = reference_tilemap.global_transform
		queue_redraw()


func _draw() -> void:
	var tile_set: TileSet = reference_tilemap.tile_set
	if tile_set == null:
		return

	var tile_size: Vector2 = Vector2(tile_set.tile_size)
	var radius: float = minf(tile_size.x, tile_size.y) * badge_radius_ratio
	var outline_width: float = radius * 0.35
	var offset: Vector2 = Vector2(0, -tile_size.y * badge_vertical_offset_ratio)

	# only the hexes with something written, the store also keeps empty ones the user opened and cleared
	var hexes: Dictionary[Vector2i, HexData] = hex_data_store.get_hexes_to_save()
	for tile_coord: Vector2i in hexes.keys():
		var center: Vector2 = reference_tilemap.map_to_local(tile_coord) + offset
		draw_circle(center, radius, hexes[tile_coord].hex_color, true, -1.0, true)
		draw_circle(center, radius, outline_color, false, outline_width, true)
