## Draws CELL paths with the mod's own path tiles, on a dedicated TileMapLayer (never on the biome layers).[br]
## Tiles are shared between paths (two roads meeting in a cell make a junction tile), so instead of building one node
## per path like [VectorPathRenderer] it redraws the whole layer for a path kind at once.[br]
## For each cell it computes the exact sides the paths leave through and looks the tile up in a [TerrainMaskIndex].
## A cell can override that with [member PathData.tile_exceptions]: a tile picked by hand, or [code]{"vector": true}[/code].
## Cells with no tile are returned so they can be drawn as short vector stubs (center to the middle of each side)
class_name TilePathRenderer extends PathRenderer


## Tiles dont meander, the line goes straight from center to center (used for bridges and picking)
func centerline(path: PathData, geometry: HexGeometry, _seed: int) -> PackedVector2Array:
	var result: PackedVector2Array = []
	if path.anchor != PathData.Anchor.CELL:
		return result
	for cell: Vector2i in path.points:
		result.append(geometry.cell_center(cell))
	return result


## Draws the paths on [param layer]. Returns the cells drawn without a tile:
## [code]{cell: {"mask": int, "connected": Array[Vector2i], "path_ids": Array[String], "forced": bool}}[/code]
func render_layer(layer: TileMapLayer, paths: Array[PathData], index: TerrainMaskIndex) -> Dictionary:
	layer.clear()
	var connected: Dictionary = {} # cell -> {neighbor cell: true}
	var owners: Dictionary = {} # cell -> Array[PathData]
	for path: PathData in paths:
		var count: int = path.points.size()
		if count < 2:
			continue
		for i: int in count:
			var cell: Vector2i = path.points[i]
			if not connected.has(cell):
				connected[cell] = {}
				owners[cell] = []
			if not owners[cell].has(path):
				owners[cell].append(path)
			if i > 0:
				connected[cell][path.points[i - 1]] = true
			if i < count - 1:
				connected[cell][path.points[i + 1]] = true

	var missing: Dictionary = {}
	for cell: Vector2i in connected.keys():
		var exception: Dictionary = exception_for(cell, owners[cell])
		var path_ids: Array[String] = []
		for owner: PathData in owners[cell]:
			path_ids.append(owner.id)

		if exception.get("vector", false):
			missing[cell] = {"mask": -1, "connected": connected[cell].keys(), "path_ids": path_ids, "forced": true}
			continue
		if exception.has("atlas_coords"):
			layer.set_cell(cell, exception.source_id, exception.atlas_coords, exception.alternative)
			continue

		var mask: int = index.mask_for(layer, cell, connected[cell])
		var entry: Dictionary = index.find(mask)
		if entry.is_empty():
			missing[cell] = {"mask": mask, "connected": connected[cell].keys(), "path_ids": path_ids, "forced": false}
		else:
			layer.set_cell(cell, entry.source_id, entry.atlas_coords, entry.alternative)
	return missing


## Exception set by hand on this cell by any of the paths going through it, parsed, or empty
static func exception_for(cell: Vector2i, paths: Array) -> Dictionary:
	var key: String = str(cell)
	for path: PathData in paths:
		if not path.tile_exceptions.has(key):
			continue
		var raw: Variant = path.tile_exceptions[key]
		if not raw is Dictionary:
			continue
		if raw.get("vector", false):
			return {"vector": true}
		var atlas_coords: Variant = str_to_var("Vector2i" + str(raw.get("atlas_coords", "")))
		if atlas_coords is Vector2i:
			return {"source_id": int(raw.get("source_id", 0)), "atlas_coords": atlas_coords, "alternative": int(raw.get("alternative", 0))}
	return {}


## Exception value saved in [member PathData.tile_exceptions] for a tile picked by hand
static func tile_exception(entry: Dictionary) -> Dictionary:
	return {"source_id": entry.source_id, "atlas_coords": str(entry.atlas_coords), "alternative": entry.alternative}


## Vector stubs for the cells without a tile: from the center to the middle of each connected side,
## through the center when the cell connects exactly 2 sides
static func build_stubs(missing: Dictionary, geometry: HexGeometry, style_for: Callable) -> Node2D:
	var root: Node2D = Node2D.new()
	root.name = "TileFallback"
	var unit: float = geometry.unit_size()
	for cell: Vector2i in missing.keys():
		var info: Dictionary = missing[cell]
		var style: PathStyle = style_for.call(info.path_ids[0])
		var center: Vector2 = geometry.cell_center(cell)
		var ends: Array[Vector2] = []
		for other: Vector2i in info.connected:
			var edge: Array = geometry.shared_edge(cell, other)
			if edge.size() == 2:
				ends.append((geometry.vertex_position(edge[0]) + geometry.vertex_position(edge[1])) / 2.0)
			else: # not neighbors anymore (tileset with another orientation), go halfway
				ends.append(center.lerp(geometry.cell_center(other), 0.5))

		var lines: Array[PackedVector2Array] = []
		if ends.size() == 2:
			lines.append(VectorPathRenderer.chaikin(PackedVector2Array([ends[0], center, ends[1]]), 2))
		else:
			for end: Vector2 in ends:
				lines.append(PackedVector2Array([center, end]))
		# every outline first so the fills join cleanly in the center
		for is_outline: bool in [true, false]:
			if is_outline and style.outline_width <= 0.0:
				continue
			for line: PackedVector2Array in lines:
				root.add_child(VectorPathRenderer.make_line(line, style, unit, is_outline, false))
	return root
