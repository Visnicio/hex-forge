## Sets up the road/river terrains of the two sample TileSets (run once, safe to run again):[br]
## [code]godot --headless --path . --script res://tools/configure_sample_terrains.gd[/code][br][br]
## - example_tileset (pixel art, flat-top): "Road" terrain on the 11 road overlays of row 9.
##   They only use the 4 diagonal sides, so roads going straight up/down fall back to vector.[br]
## - david_baumgart_packed (pointy-top): "River" terrain on 3 river overlays, plus mirrored alternatives
##   (flip h/v) to cover more combinations. Flipping vertically moves the hex art inside the taller region,
##   so those alternatives get a texture_origin that puts it back.[br]
## Sides are written as screen directions and converted to the CellNeighbor whose neighbor cell really is in that
## direction, so a wrong guess about Godot's side naming fails loudly instead of producing broken tiles
extends SceneTree

const EXAMPLE_PATH: String = "res://resources/tilesets/example_tileset.tres"
const DAVID_PATH: String = "res://resources/tilesets/david_baumgart_packed.tres"

## atlas coords -> screen directions of the sides the road leaves through
const EXAMPLE_ROADS: Dictionary = {
	Vector2i(0, 9): ["top-left", "top-right", "bottom-left", "bottom-right"],
	Vector2i(1, 9): ["bottom-left", "top-right"],
	Vector2i(2, 9): ["top-left", "bottom-right"],
	Vector2i(3, 9): ["top-left", "bottom-left"],
	Vector2i(4, 9): ["top-right", "bottom-right"],
	Vector2i(5, 9): ["bottom-left", "bottom-right"],
	Vector2i(6, 9): ["top-left", "top-right"],
	Vector2i(7, 9): ["top-left", "bottom-left", "bottom-right"],
	Vector2i(8, 9): ["bottom-left", "top-right", "bottom-right"],
	Vector2i(9, 9): ["top-left", "top-right", "bottom-left"],
	Vector2i(10, 9): ["top-left", "top-right", "bottom-right"],
}

## David's file names (hexRiverLakeEnd010000, hexRiver010010, hexRiver001010) give the connections.
## (1, 3) doesnt reach any side of the hex, so it isnt used
const DAVID_RIVERS: Dictionary = {
	Vector2i(6, 3): ["top-right"],
	Vector2i(7, 3): ["bottom-left", "top-right"],
	Vector2i(0, 4): ["right", "bottom-left"],
}

const DIRECTIONS: Dictionary = {
	"right": Vector2(1, 0), "left": Vector2(-1, 0), "top": Vector2(0, -1), "bottom": Vector2(0, 1),
	"top-right": Vector2(1, -1), "top-left": Vector2(-1, -1), "bottom-right": Vector2(1, 1), "bottom-left": Vector2(-1, 1),
}


func _init() -> void:
	var ok: bool = _configure(EXAMPLE_PATH, "Road", Color(0.62, 0.55, 0.45), EXAMPLE_ROADS, false)
	ok = _configure(DAVID_PATH, "River", Color(0.25, 0.55, 0.85), DAVID_RIVERS, true) and ok
	quit(0 if ok else 1)


func _configure(path: String, terrain_name: String, color: Color, tiles: Dictionary, add_mirrors: bool) -> bool:
	var tile_set: TileSet = load(path) # normal load keeps the uid when saving back
	var source: TileSetAtlasSource = tile_set.get_source(0)
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = tile_set
	root.add_child(layer)

	# terrain set 0 is reserved for paths, created if missing
	if tile_set.get_terrain_sets_count() == 0:
		tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	if tile_set.get_terrains_count(0) == 0:
		tile_set.add_terrain(0)
	tile_set.set_terrain_name(0, 0, terrain_name)
	tile_set.set_terrain_color(0, 0, color)

	var side_by_direction: Dictionary = _sides_by_direction(layer, tile_set)
	print("%s sides: %s" % [path.get_file(), side_by_direction])

	var region: Vector2 = Vector2(source.texture_region_size)
	var art_offset_y: float = maxf(region.y - float(tile_set.tile_size.y), 0.0) / 2.0

	for atlas_coords: Vector2i in tiles.keys():
		if not source.has_tile(atlas_coords):
			printerr("missing tile ", atlas_coords)
			return false
		var directions: Array = tiles[atlas_coords]
		for direction: String in directions:
			if not side_by_direction.has(direction):
				printerr("%s has no side towards %s" % [path.get_file(), direction])
				return false

		var variants: Array = [[false, false]]
		if add_mirrors:
			variants = [[false, false], [true, false], [false, true], [true, true]]
		for variant: Array in variants:
			var flip_h: bool = variant[0]
			var flip_v: bool = variant[1]
			var alternative: int = _find_or_create_alternative(source, atlas_coords, flip_h, flip_v)
			var data: TileData = source.get_tile_data(atlas_coords, alternative)
			data.flip_h = flip_h
			data.flip_v = flip_v
			# a vertical flip mirrors the whole taller region, which moves the hex art up, this moves it back down
			data.texture_origin = Vector2i(0, -int(art_offset_y * 2.0)) if flip_v else Vector2i.ZERO
			data.terrain_set = 0
			data.terrain = 0
			for side: int in side_by_direction.values():
				data.set_terrain_peering_bit(side, -1)
			for direction: String in directions:
				var mirrored: Vector2 = DIRECTIONS[direction] * Vector2(-1.0 if flip_h else 1.0, -1.0 if flip_v else 1.0)
				data.set_terrain_peering_bit(side_by_direction[_closest_direction(mirrored, side_by_direction)], 0)

	var original_text: String = FileAccess.get_file_as_string(path)
	var error: Error = ResourceSaver.save(tile_set, path)
	if error == OK:
		_restore_uids(path, original_text)
	print("saved %s: %s" % [path.get_file(), error_string(error)])
	return error == OK


## Saving from --script mode drops the uid="..." of the file and of its ext_resources (no editor uid cache),
## other resources reference the tileset by uid, so the original lines are put back
static func _restore_uids(path: String, original_text: String) -> void:
	var saved_text: String = FileAccess.get_file_as_string(path)
	var uid_pattern: RegEx = RegEx.create_from_string(" uid=\"[^\"]*\"")
	for line: String in original_text.split("\n"):
		if not line.begins_with("[") or uid_pattern.search(line) == null:
			continue
		var without_uid: String = uid_pattern.sub(line, "", true)
		saved_text = saved_text.replace(without_uid, line)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(saved_text)
	file.close()


## Screen direction name -> side CellNeighbor, measured from real neighbor positions
func _sides_by_direction(layer: TileMapLayer, tile_set: TileSet) -> Dictionary:
	var result: Dictionary = {}
	var center: Vector2 = layer.map_to_local(Vector2i(4, 4))
	for side: int in TerrainMaskIndex.side_neighbors(tile_set):
		var offset: Vector2 = layer.map_to_local(layer.get_neighbor_cell(Vector2i(4, 4), side)) - center
		var direction: String = _closest_direction(offset, DIRECTIONS)
		result[direction] = side
	return result


static func _closest_direction(vector: Vector2, candidates: Dictionary) -> String:
	var best: String = ""
	var best_dot: float = -INF
	for direction: String in candidates.keys():
		var dot: float = vector.normalized().dot((DIRECTIONS[direction] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best = direction
	return best


static func _find_or_create_alternative(source: TileSetAtlasSource, atlas_coords: Vector2i, flip_h: bool, flip_v: bool) -> int:
	if not flip_h and not flip_v:
		return 0
	for i: int in source.get_alternative_tiles_count(atlas_coords):
		var alternative: int = source.get_alternative_tile_id(atlas_coords, i)
		var data: TileData = source.get_tile_data(atlas_coords, alternative)
		if alternative != 0 and data.flip_h == flip_h and data.flip_v == flip_v:
			return alternative
	return source.create_alternative_tile(atlas_coords)
