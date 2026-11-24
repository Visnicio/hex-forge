## Checks what a tileset mod offers to the roads/rivers/smoothing features, what is missing and which fallback the
## editor will use instead. Nothing here is required: every row that isnt "ok" still works, just with a fallback.[br]
## Each row: [code]{feature, status ("ok" | "fallback" | "error"), detail}[/code]
class_name ModLint extends RefCounted

const OK: String = "ok"
const FALLBACK: String = "fallback"
const ERROR: String = "error"


static func inspect(config: MapTilesetConfiguration) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if config == null:
		rows.append(_row("Configuration", ERROR, "No MapTilesetConfiguration"))
		return rows
	var tile_set: TileSet = config.tileset_resource
	if tile_set == null:
		rows.append(_row("TileSet", ERROR, "tileset_resource is empty, the map cant be drawn"))
		return rows

	rows.append(_tileset_row(tile_set))

	var probe: TileMapLayer = TileMapLayer.new()
	probe.tile_set = tile_set
	var geometry: HexGeometry = HexGeometry.new(probe, config)
	if config.auto_hex_art_offset:
		rows.append(_row("Hex art alignment", FALLBACK, "Guessed: art centered %s from the cell (set hex_art_offset if roads look shifted)" % geometry.art_offset))
	else:
		rows.append(_row("Hex art alignment", OK, "Set by the mod: %s" % config.hex_art_offset))

	rows.append(_path_tiles_row("Road tiles", tile_set, config.road_terrain_set, config.road_terrain, "roads"))
	rows.append(_path_tiles_row("River tiles (rivers by centers)", tile_set, config.river_terrain_set, config.river_terrain, "rivers"))
	rows.append(_styles_row(config))

	var ground_tiles: Array[Array] = _ground_tiles(tile_set)
	rows.append(_custom_data_row(tile_set, TileColorCache.LAYER_IS_WATER, TYPE_BOOL, "Water (is_water)",
		"%d tile(s) look like water by their color" % ground_tiles.filter(func(tile: Array) -> bool:
			return TileColorCache.looks_like_water(TileColorCache.average_color(tile_set, tile[0], tile[1]))).size()))
	rows.append(_custom_data_row(tile_set, TileColorCache.LAYER_BLEND_COLOR, TYPE_COLOR, "Blend color (blend_color)",
		"Average color of each tile is used"))
	rows.append(_custom_data_row(tile_set, TileColorCache.LAYER_BIOME, TYPE_STRING, "Biome (biome)",
		"Not used yet, only reported here"))

	var overhang: OverhangPass = OverhangPass.new()
	overhang.configure([], geometry)
	var tall: int = 0
	for source_tiles: Dictionary in overhang._overhang_tiles.values():
		tall += source_tiles.size()
	overhang.free()
	if tall > 0:
		rows.append(_row("Tall tiles", OK, "%d tile(s) stick out of their hex, they are redrawn above roads/rivers" % tall))
	else:
		rows.append(_row("Tall tiles", OK, "None, every tile fits its hex"))
	probe.free()
	return rows


static func _row(feature: String, status: String, detail: String) -> Dictionary:
	return {"feature": feature, "status": status, "detail": detail}


static func _tileset_row(tile_set: TileSet) -> Dictionary:
	if tile_set.tile_shape != TileSet.TILE_SHAPE_HEXAGON:
		return _row("TileSet", ERROR, "Not a hexagon tileset, roads/rivers/smoothing expect hexes")
	var orientation: String = "pointy-top" if tile_set.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL else "flat-top"
	return _row("TileSet", OK, "Hexagon %s, tile size %s, %d source(s)" % [orientation, tile_set.tile_size, tile_set.get_source_count()])


static func _path_tiles_row(feature: String, tile_set: TileSet, terrain_set: int, terrain: int, what: String) -> Dictionary:
	if terrain_set < 0 or terrain < 0:
		return _row(feature, FALLBACK, "Not provided, %s are drawn as vector lines" % what)
	var index: TerrainMaskIndex = TerrainMaskIndex.build(tile_set, terrain_set, terrain)
	if index == null:
		return _row(feature, ERROR, "terrain set %d / terrain %d is invalid (or has no side peering bits), %s fall back to vector" % [terrain_set, terrain, what])
	var coverage: Vector2i = index.coverage()
	var status: String = OK if coverage.x == coverage.y else FALLBACK
	return _row(feature, status, "%d tile(s) covering %d of %d side combinations, the rest is drawn as vector" % [index.entries().size(), coverage.x, coverage.y])


static func _styles_row(config: MapTilesetConfiguration) -> Dictionary:
	if config.path_styles.is_empty():
		return _row("Path styles", FALLBACK, "None, the built-in styles are used")
	var ids: Dictionary = {}
	for style: PathStyle in PathStyles.BUILTIN_STYLES:
		ids[style.id] = true
	for style: PathStyle in config.path_styles:
		if style == null or style.id.is_empty():
			return _row("Path styles", ERROR, "A style has no id")
		if ids.has(style.id):
			return _row("Path styles", ERROR, "Style id '%s' is used twice" % style.id)
		ids[style.id] = true
	return _row("Path styles", OK, "%d extra style(s)" % config.path_styles.size())


static func _custom_data_row(tile_set: TileSet, layer_name: String, type: int, feature: String, fallback: String) -> Dictionary:
	var layer: int = tile_set.get_custom_data_layer_by_name(layer_name)
	if layer == -1:
		return _row(feature, FALLBACK, "Not provided. " + fallback)
	if tile_set.get_custom_data_layer_type(layer) != type:
		return _row(feature, ERROR, "Custom data layer '%s' should be of type %s" % [layer_name, type_string(type)])
	return _row(feature, OK, "Provided by the mod")


## Tiles that arent part of a road/river terrain, [source_id, atlas_coords]
static func _ground_tiles(tile_set: TileSet) -> Array[Array]:
	var result: Array[Array] = []
	for source_index: int in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(source_index)
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index: int in source.get_tiles_count():
			var atlas_coords: Vector2i = source.get_tile_id(tile_index)
			if source.get_tile_data(atlas_coords, 0).terrain_set == -1:
				result.append([source_id, atlas_coords])
	return result
