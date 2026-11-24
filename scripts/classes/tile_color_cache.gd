## Per tile data used by the biome smoothing and the coastlines, from the TileSet custom data when the mod
## provides it, otherwise computed:[br]
## - [code]blend_color[/code] (Color): falls back to the average color of the tile art inside its hex[br]
## - [code]is_water[/code] (bool): falls back to "is the average color clearly blue"[br]
## - [code]biome[/code] (String): only reported for now (mod lint), empty when missing[br]
## Everything is cached per TileSet, the atlas is only read for tiles actually asked for
class_name TileColorCache extends RefCounted

const LAYER_BIOME: String = "biome"
const LAYER_IS_WATER: String = "is_water"
const LAYER_BLEND_COLOR: String = "blend_color"

static var _colors: Dictionary = {} # "tileset_id|source|coords" -> Color
static var _images: Dictionary = {} # "tileset_id|source" -> Image


static func blend_color(tile_set: TileSet, source_id: int, atlas_coords: Vector2i, alternative: int = 0) -> Color:
	var data: TileData = _tile_data(tile_set, source_id, atlas_coords, alternative)
	if data != null and tile_set.get_custom_data_layer_by_name(LAYER_BLEND_COLOR) != -1:
		var custom: Variant = data.get_custom_data(LAYER_BLEND_COLOR)
		if custom is Color and (custom as Color).a > 0.0:
			return custom
	return average_color(tile_set, source_id, atlas_coords)


static func is_water(tile_set: TileSet, source_id: int, atlas_coords: Vector2i, alternative: int = 0) -> bool:
	var data: TileData = _tile_data(tile_set, source_id, atlas_coords, alternative)
	if data != null and tile_set.get_custom_data_layer_by_name(LAYER_IS_WATER) != -1:
		return bool(data.get_custom_data(LAYER_IS_WATER))
	return looks_like_water(average_color(tile_set, source_id, atlas_coords))


static func biome(tile_set: TileSet, source_id: int, atlas_coords: Vector2i, alternative: int = 0) -> String:
	var data: TileData = _tile_data(tile_set, source_id, atlas_coords, alternative)
	if data != null and tile_set.get_custom_data_layer_by_name(LAYER_BIOME) != -1:
		return str(data.get_custom_data(LAYER_BIOME))
	return ""


## Clearly blue and saturated (ocean, lake), not pale blue (snow, ice) nor green with puddles (marsh)
static func looks_like_water(color: Color) -> bool:
	return color.b > color.r + 0.12 and color.b > color.g + 0.02 and color.s > 0.35 and color.a > 0.5


## Alpha weighted average of the tile art inside the top/middle of its region (skips the transparent overhang area
## and most of the base rim), sampled on a grid so big atlases stay fast
static func average_color(tile_set: TileSet, source_id: int, atlas_coords: Vector2i) -> Color:
	var key: String = "%d|%d|%s" % [tile_set.get_instance_id(), source_id, atlas_coords]
	if _colors.has(key):
		return _colors[key]
	var color: Color = Color(0.5, 0.5, 0.5, 0.0)
	var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource if tile_set.has_source(source_id) else null
	if source != null and source.has_tile(atlas_coords):
		var image: Image = _image_of(tile_set, source_id, source)
		if image != null:
			color = _average(image, source.get_tile_texture_region(atlas_coords), tile_set.tile_size)
	_colors[key] = color
	return color


static func _average(image: Image, region: Rect2i, tile_size: Vector2i) -> Color:
	# the hex is at the bottom of taller regions, only look at a centered box of the hex size there
	var box: Rect2i = Rect2i(region.position + Vector2i(0, region.size.y - tile_size.y), tile_size)
	box = box.grow_individual(-tile_size.x / 6, -tile_size.y / 6, -tile_size.x / 6, -tile_size.y / 6)
	var stride: int = maxi(box.size.x / 24, 1)
	var sum: Color = Color(0, 0, 0, 0)
	var weight: float = 0.0
	for y: int in range(box.position.y, box.end.y, stride):
		for x: int in range(box.position.x, box.end.x, stride):
			if x >= image.get_width() or y >= image.get_height():
				continue
			var pixel: Color = image.get_pixel(x, y)
			sum += Color(pixel.r * pixel.a, pixel.g * pixel.a, pixel.b * pixel.a, 0.0)
			weight += pixel.a
	if weight <= 0.0:
		return Color(0.5, 0.5, 0.5, 0.0)
	return Color(sum.r / weight, sum.g / weight, sum.b / weight, 1.0)


static func _image_of(tile_set: TileSet, source_id: int, source: TileSetAtlasSource) -> Image:
	var key: String = "%d|%d" % [tile_set.get_instance_id(), source_id]
	if not _images.has(key):
		var image: Image = source.texture.get_image() if source.texture else null
		if image != null and image.is_compressed():
			image.decompress()
		_images[key] = image
	return _images[key]


static func _tile_data(tile_set: TileSet, source_id: int, atlas_coords: Vector2i, alternative: int) -> TileData:
	if not tile_set.has_source(source_id):
		return null
	var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or not source.has_tile(atlas_coords) or not source.has_alternative_tile(atlas_coords, alternative):
		return null
	return source.get_tile_data(atlas_coords, alternative)
