## Shallow water and a foam line along every edge between a water hex and a land hex, drawn over the ground.[br]
## Water comes from the TileSet custom data [code]is_water[/code] when the mod has it, otherwise from the average
## color of the tile ([TileColorCache]). Colors come from [code]blend_color[/code] or the average color too.[br]
## The edge wiggles with the same stable seeded meander as rivers (keyed by the edge corners), so editing the map
## somewhere else never moves this coastline
class_name CoastlineOverlay extends Node2D

## Shallow water band width, fraction of the way from the edge to the water hex center
const BAND: float = 0.3

var _dirty: bool = true
var _bands: Array[Dictionary] = [] # {points: PackedVector2Array, inner: PackedVector2Array, color: Color}
var _lines: Array[Dictionary] = [] # {points, color, width}
var _style: PathStyle


func _init() -> void:
	_style = PathStyle.new()
	_style.meander_amplitude = 0.12
	_style.meander_depth = 2
	_style.smoothing_iterations = 2


func mark_dirty() -> void:
	_dirty = true


## Rebuilds when something changed, called every frame by [GroundBlend]
func update(ground_layers: Array[TileMapLayer], geometry: HexGeometry, seed: int, tilemap_transform: Transform2D) -> void:
	if not _dirty or not visible:
		return
	_dirty = false
	global_transform = tilemap_transform
	_bands.clear()
	_lines.clear()
	if geometry != null and geometry.is_valid():
		_build(ground_layers, geometry, seed)
	queue_redraw()


## Number of water/land edges drawn (used by tests)
func edge_count() -> int:
	return _lines.size()


func _build(ground_layers: Array[TileMapLayer], geometry: HexGeometry, seed: int) -> void:
	var tile_set: TileSet = geometry.layer.tile_set
	# what each cell shows: the top-most ground layer with a tile there
	var top_tiles: Dictionary = {} # cell -> [source_id, atlas_coords, alternative]
	for layer: TileMapLayer in ground_layers:
		if not is_instance_valid(layer):
			continue
		for cell: Vector2i in layer.get_used_cells():
			top_tiles[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]

	var water: Dictionary = {}
	for cell: Vector2i in top_tiles.keys():
		var tile: Array = top_tiles[cell]
		water[cell] = TileColorCache.is_water(tile_set, tile[0], tile[1], tile[2])

	var unit: float = geometry.unit_size()
	for cell: Vector2i in top_tiles.keys():
		if not water[cell]:
			continue
		var tile: Array = top_tiles[cell]
		var water_color: Color = TileColorCache.blend_color(tile_set, tile[0], tile[1], tile[2])
		var shallow: Color = water_color.lightened(0.35)
		var center: Vector2 = geometry.cell_center(cell)
		for other: Vector2i in geometry.neighbors(cell):
			if not top_tiles.has(other) or water[other]:
				continue
			var land_tile: Array = top_tiles[other]
			var land_color: Color = TileColorCache.blend_color(tile_set, land_tile[0], land_tile[1], land_tile[2])
			var edge: Array = geometry.shared_edge(cell, other)
			if edge.size() != 2:
				continue
			var key_a: String = HexGeometry.vertex_to_string(edge[0])
			var key_b: String = HexGeometry.vertex_to_string(edge[1])
			var points: PackedVector2Array = VectorPathRenderer.chaikin(VectorPathRenderer.meander_segment(
				geometry.vertex_position(edge[0]), geometry.vertex_position(edge[1]), key_a, key_b, _style, seed), 2)
			var inner: PackedVector2Array = []
			for point: Vector2 in points:
				inner.append(point.lerp(center, BAND))
			_bands.append({"points": points, "inner": inner, "color": Color(shallow, 0.85)})
			# foam: a light version of the land color, so sand gives a sandy beach and grass a pale shore
			_lines.append({"points": points, "color": Color(land_color.lerp(Color(0.97, 0.95, 0.85), 0.6), 0.9), "width": unit * 0.03})


func _draw() -> void:
	for band: Dictionary in _bands:
		var points: PackedVector2Array = band.points
		var inner: PackedVector2Array = band.inner
		var color: Color = band.color
		var clear: Color = Color(color, 0.0)
		for i: int in points.size() - 1:
			draw_polygon(PackedVector2Array([points[i], points[i + 1], inner[i + 1], inner[i]]),
				PackedColorArray([color, color, clear, clear]))
	for line: Dictionary in _lines:
		draw_polyline(line.points, line.color, line.width, true)
