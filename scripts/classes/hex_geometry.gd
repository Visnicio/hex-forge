## Hex geometry of the open map, built on top of a reference [TileMapLayer].[br]
## There is NO hardcoded hex math here: tilesets vary between pointy-top and flat-top (and layouts),
## so everything comes from [method TileMapLayer.map_to_local], [method TileMapLayer.local_to_map]
## and [method TileMapLayer.get_surrounding_cells] (which returns the 6 neighbors in angular order).[br]
## A hex corner is the average of the centers of a cell and two consecutive neighbors.[br][br]
## Positions are in the tilemap local space (tile pixels, before the tilemap scale), offset by
## [member art_offset] so they line up with where the hex ART is drawn, not the logical cell center
## (tiles taller than the hex are drawn centered on the cell, which pushes the hex art down).[br][br]
## A vertex (corner) is identified by the sorted trio of the 3 cells that meet there, which doesnt depend on
## the tile orientation nor on a corner index. If the trio stops being adjacent (e.g. after swapping to a tileset
## with another orientation) its position falls back to the centroid of the 3 centers, which is still a sane point
class_name HexGeometry extends RefCounted

var layer: TileMapLayer
## Where the hex art center is relative to [method TileMapLayer.map_to_local], in tile pixels
var art_offset: Vector2 = Vector2.ZERO

var _neighbors_cache: Dictionary[Vector2i, Array] = {}


func _init(reference_layer: TileMapLayer, config: MapTilesetConfiguration = null) -> void:
	layer = reference_layer
	if layer != null and layer.tile_set != null:
		art_offset = compute_art_offset(layer.tile_set, config)


func is_valid() -> bool:
	return layer != null and layer.tile_set != null


## Size used to scale widths of paths, so styles look the same on 28px and 256px hexes
func unit_size() -> float:
	var tile_size: Vector2i = layer.tile_set.tile_size
	return float(mini(tile_size.x, tile_size.y))


## Offset between the logical cell center and the center of the hex art.[br]
## Uses the config override when the modder set one, otherwise assumes the hex art sits at the bottom of a
## taller texture region (the usual way of drawing tall tiles) and takes the tile texture_origin into account
static func compute_art_offset(tile_set: TileSet, config: MapTilesetConfiguration) -> Vector2:
	if config != null and not config.auto_hex_art_offset:
		return config.hex_art_offset

	for source_index: int in tile_set.get_source_count():
		var source: TileSetAtlasSource = tile_set.get_source(tile_set.get_source_id(source_index)) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var tile_coords: Vector2i = source.get_tile_id(0)
		var region_size: Vector2 = Vector2(source.get_tile_texture_region(tile_coords).size)
		var tile_data: TileData = source.get_tile_data(tile_coords, 0)
		var extra_height: float = maxf(region_size.y - float(tile_set.tile_size.y), 0.0)
		# the texture is drawn at (cell_center - region_size / 2 - texture_origin)
		return Vector2(0.0, extra_height / 2.0) - Vector2(tile_data.texture_origin)

	return Vector2.ZERO


# --- cells ---

func cell_center(cell: Vector2i) -> Vector2:
	return layer.map_to_local(cell) + art_offset


func cell_at(local_position: Vector2) -> Vector2i:
	return layer.local_to_map(local_position - art_offset)


## The 6 neighbors in angular order (cached, this is called a lot while rendering)
func neighbors(cell: Vector2i) -> Array:
	if not _neighbors_cache.has(cell):
		_neighbors_cache[cell] = layer.get_surrounding_cells(cell)
	return _neighbors_cache[cell]


func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return neighbors(a).has(b)


## The 6 corners of the cell, in the same angular order as [method neighbors]
func corners(cell: Vector2i) -> PackedVector2Array:
	var result: PackedVector2Array = []
	var around: Array = neighbors(cell)
	for i: int in around.size():
		result.append(vertex_position(make_vertex(cell, around[i], around[(i + 1) % around.size()])))
	return result


## Corners of the cell relative to its center, same for every cell of the map
func corner_offsets() -> PackedVector2Array:
	var result: PackedVector2Array = corners(Vector2i.ZERO)
	var center: Vector2 = cell_center(Vector2i.ZERO)
	for i: int in result.size():
		result[i] -= center
	return result


# --- vertices ---

## Canonical id of the corner shared by 3 cells, the order of the arguments doesnt matter
static func make_vertex(a: Vector2i, b: Vector2i, c: Vector2i) -> Array:
	var trio: Array = [a, b, c]
	trio.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x < q.x or (p.x == q.x and p.y < q.y))
	return trio


static func vertex_to_string(vertex: Array) -> String:
	return "%s|%s|%s" % [vertex[0], vertex[1], vertex[2]]


## Returns [code]null[/code] if the string isnt a valid trio
static func vertex_from_string(raw: String) -> Variant:
	var parts: PackedStringArray = raw.split("|")
	if parts.size() != 3:
		return null
	var cells: Array = []
	for part: String in parts:
		var cell: Variant = str_to_var("Vector2i" + part.strip_edges())
		if not cell is Vector2i:
			return null
		cells.append(cell)
	return make_vertex(cells[0], cells[1], cells[2])


func vertex_position(vertex: Array) -> Vector2:
	return (cell_center(vertex[0]) + cell_center(vertex[1]) + cell_center(vertex[2])) / 3.0


## True when the 3 cells really touch each other (false after swapping to a tileset with another orientation)
func is_vertex_valid(vertex: Array) -> bool:
	return are_adjacent(vertex[0], vertex[1]) and are_adjacent(vertex[1], vertex[2]) and are_adjacent(vertex[0], vertex[2])


func cell_vertices(cell: Vector2i) -> Array:
	var result: Array = []
	var around: Array = neighbors(cell)
	for i: int in around.size():
		result.append(make_vertex(cell, around[i], around[(i + 1) % around.size()]))
	return result


## The (up to 3) corners connected to this one by a hex edge
func vertex_neighbors(vertex: Array) -> Array:
	var result: Array = []
	for pair: Array in [[0, 1], [1, 2], [0, 2]]:
		var a: Vector2i = vertex[pair[0]]
		var b: Vector2i = vertex[pair[1]]
		for other: Vector2i in common_neighbors(a, b):
			if not vertex.has(other):
				result.append(make_vertex(a, b, other))
	return result


func are_vertices_adjacent(v1: Array, v2: Array) -> bool:
	var shared: int = 0
	for cell: Vector2i in v1:
		if v2.has(cell):
			shared += 1
	return shared == 2 and v1 != v2


## Cells that are neighbors of both a and b (2 for adjacent cells)
func common_neighbors(a: Vector2i, b: Vector2i) -> Array:
	var result: Array = []
	var around_b: Array = neighbors(b)
	for cell: Vector2i in neighbors(a):
		if around_b.has(cell):
			result.append(cell)
	return result


## The 2 corners of the edge between 2 adjacent cells, empty if they arent adjacent
func shared_edge(a: Vector2i, b: Vector2i) -> Array:
	var result: Array = []
	for other: Vector2i in common_neighbors(a, b):
		result.append(make_vertex(a, b, other))
	return result


func nearest_vertex(local_position: Vector2) -> Array:
	var best: Array = []
	var best_distance: float = INF
	for vertex: Array in cell_vertices(cell_at(local_position)):
		var distance: float = vertex_position(vertex).distance_squared_to(local_position)
		if distance < best_distance:
			best_distance = distance
			best = vertex
	return best


## Shortest chain of edges from one corner to another (excluding [param from]), empty if too far.[br]
## Used when the mouse skips corners while dragging a river
func vertex_route(from: Array, to: Array, max_steps: int = 24) -> Array:
	if from == to:
		return []
	var from_key: String = vertex_to_string(from)
	var to_key: String = vertex_to_string(to)
	var came_from: Dictionary = {from_key: null}
	var vertices_by_key: Dictionary = {from_key: from}
	var frontier: Array = [from]

	for _step: int in max_steps:
		var next_frontier: Array = []
		for vertex: Array in frontier:
			for next: Array in vertex_neighbors(vertex):
				var next_key: String = vertex_to_string(next)
				if came_from.has(next_key):
					continue
				came_from[next_key] = vertex_to_string(vertex)
				vertices_by_key[next_key] = next
				if next_key == to_key:
					var route: Array = []
					var key: Variant = to_key
					while key != from_key:
						route.push_front(vertices_by_key[key])
						key = came_from[key]
					return route
				next_frontier.append(next)
		frontier = next_frontier
	return []


## Cells crossed by the straight line between 2 cell centers (excluding [param from]), each one adjacent to the previous.[br]
## Used when the mouse skips cells while dragging a road
func cell_route(from: Vector2i, to: Vector2i) -> Array:
	var result: Array = []
	var start: Vector2 = cell_center(from)
	var end: Vector2 = cell_center(to)
	var steps: int = maxi(int(start.distance_to(end) / (unit_size() * 0.2)), 1)
	var last: Vector2i = from
	for i: int in range(1, steps + 1):
		var cell: Vector2i = cell_at(start.lerp(end, float(i) / steps))
		if cell == last:
			continue
		if not are_adjacent(last, cell):
			# the line went exactly through a corner, step through one of the cells touching both
			var bridge: Array = common_neighbors(last, cell)
			if bridge.is_empty():
				return result # shouldnt happen with small steps, stop instead of making a broken path
			result.append(bridge[0])
		result.append(cell)
		last = cell
	return result
