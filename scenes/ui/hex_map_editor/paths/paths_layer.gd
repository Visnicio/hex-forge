## Draws every road/river of the [PathStore] in the map, right above the "anchor" user layer
## (the ground) and below the layers on top of it (decals...), then the [OverhangPass] on top so tall art
## still covers the paths behind it.[br]
## Lives in the same space as the tilemaps (copies the reference tilemap transform, like [HexDataIndicators]).[br]
## Each path is drawn by a [PathRenderer] picked by [method effective_mode]: the mod's own tiles when it declares a
## road/river terrain ([TilePathRenderer]), vector lines otherwise ([VectorPathRenderer]).[br]
## Draw order inside: river tiles, rivers, road tiles, roads, bridges, overhang
class_name PathsLayer extends Node2D

## Emitted after the tile layers were redrawn, so the panel can show which hexes had no tile
signal tiles_rebuilt()

## Every layer shares the pencil tileset and scale, so its used for the hex geometry
@export var reference_tilemap: TileMapLayer
@export var path_store: PathStore
@export var editor: HexMapEditor

var geometry: HexGeometry
var vector_renderer: VectorPathRenderer = VectorPathRenderer.new()
var tile_renderer: TilePathRenderer = TilePathRenderer.new()

## Road/river tiles of the current mod, null when it doesnt provide them
var _indices: Dictionary[int, TerrainMaskIndex] = {}
var _tile_layers: Dictionary[int, TileMapLayer] = {}
var _vector_roots: Dictionary[int, Node2D] = {}
var _fallback_nodes: Dictionary[int, Node2D] = {}
## Cells drawn as vector because the mod has no tile for them: kind -> {cell: info} (see [method TilePathRenderer.render_layer])
var _missing_tiles: Dictionary[int, Dictionary] = {}
var _tiles_dirty: Dictionary[int, bool] = {}
var _bridges: BridgesDrawer
var _overhang: OverhangPass

## User layers at or below the anchor (the "ground"), bottom first. Read by the biome smoothing too
var ground_layers: Array[TileMapLayer] = []
## Changes whenever [member ground_layers] or their order changes
var ground_signature: String = ""

var _path_nodes: Dictionary[String, Node2D] = {}
## Drawn centerline of every path, used for bridges and picking paths with the mouse
var _centerlines: Dictionary[String, PackedVector2Array] = {}

# polled state, theres no signal for tileset/scale/layer order changes
var _last_tileset: TileSet
var _last_config: MapTilesetConfiguration
var _last_scale: Vector2
var _last_layers_signature: String = ""
var _bridges_dirty: bool = false


func _ready() -> void:
	for kind: int in [PathData.Kind.RIVER, PathData.Kind.ROAD]:
		var kind_name: String = PathData.KIND_NAMES[kind].capitalize()
		var tiles: TileMapLayer = TileMapLayer.new()
		tiles.name = kind_name + "Tiles"
		add_child(tiles)
		_tile_layers[kind] = tiles
		var vectors: Node2D = Node2D.new()
		vectors.name = kind_name + "s"
		add_child(vectors)
		_vector_roots[kind] = vectors
		_missing_tiles[kind] = {}
	_bridges = BridgesDrawer.new()
	_bridges.name = "Bridges"
	add_child(_bridges)
	_overhang = OverhangPass.new()
	_overhang.name = "Overhang"
	add_child(_overhang)

	path_store.path_changed.connect(_on_path_changed)
	path_store.store_reset.connect(rebuild_all)
	path_store.settings_changed.connect(func() -> void:
		_last_layers_signature = ""
		rebuild_all())


func _process(_delta: float) -> void:
	var config: MapTilesetConfiguration = editor.current_map_tileset_configuration if editor else null
	if reference_tilemap.tile_set != _last_tileset or reference_tilemap.scale != _last_scale or config != _last_config:
		_last_tileset = reference_tilemap.tile_set
		_last_scale = reference_tilemap.scale
		_last_config = config
		global_transform = reference_tilemap.global_transform
		_setup_tileset(config)
		_last_layers_signature = "" # forces the overhang to reconfigure with the new geometry
		rebuild_all()

	_update_anchor()

	for kind: int in _tiles_dirty.keys():
		if _tiles_dirty[kind]:
			_tiles_dirty[kind] = false
			_rebuild_tiles(kind)
			_bridges_dirty = true
	if _bridges_dirty:
		_bridges_dirty = false
		_rebuild_bridges()


func _setup_tileset(config: MapTilesetConfiguration) -> void:
	geometry = HexGeometry.new(reference_tilemap, config)
	_indices.clear()
	for kind: int in _tile_layers.keys():
		_tile_layers[kind].tile_set = reference_tilemap.tile_set

	var extra_styles: Array[PathStyle] = []
	if config != null and reference_tilemap.tile_set != null:
		extra_styles = config.path_styles
		_indices[PathData.Kind.ROAD] = TerrainMaskIndex.build(reference_tilemap.tile_set, config.road_terrain_set, config.road_terrain)
		_indices[PathData.Kind.RIVER] = TerrainMaskIndex.build(reference_tilemap.tile_set, config.river_terrain_set, config.river_terrain)
	PathStyles.set_extra_styles(extra_styles)


## The pass that redraws tall art above the paths
func overhang() -> OverhangPass:
	return _overhang


## True when paths can be drawn (theres a tileset)
func is_ready() -> bool:
	return geometry != null and geometry.is_valid()


## Path tiles the current mod provides for the kind, or null
func index_for(kind: PathData.Kind) -> TerrainMaskIndex:
	return _indices.get(kind, null)


## "tile" or "vector": the path's own mode, else the map default, else tiles when the mod has them.
## Only paths through the hex centers can use tiles
func effective_mode(path: PathData) -> String:
	var mode: String = path.render_mode
	if mode == "auto":
		mode = path_store.render_mode
	if mode == "vector" or path.anchor != PathData.Anchor.CELL or index_for(path.kind) == null:
		return "vector"
	return "tile"


## Cells of this path drawn in vector because the mod has no tile for them (or they were set to vector by hand)
func missing_tiles_of(path: PathData) -> Dictionary:
	var result: Dictionary = {}
	var missing: Dictionary = _missing_tiles.get(path.kind, {})
	for cell: Vector2i in missing.keys():
		if missing[cell].path_ids.has(path.id):
			result[cell] = missing[cell]
	return result


func get_centerline(path_id: String) -> PackedVector2Array:
	return _centerlines.get(path_id, PackedVector2Array())


func rebuild_all() -> void:
	for node: Node2D in _path_nodes.values():
		node.queue_free()
	_path_nodes.clear()
	_centerlines.clear()
	if is_ready():
		for path: PathData in path_store.get_all_paths():
			_build_path(path)
	for kind: int in _tile_layers.keys():
		_tiles_dirty[kind] = true
	_bridges_dirty = true


func _on_path_changed(path_id: String) -> void:
	if _path_nodes.has(path_id):
		_path_nodes[path_id].queue_free()
		_path_nodes.erase(path_id)
	_centerlines.erase(path_id)
	var path: PathData = path_store.get_path_data(path_id)
	if path != null and is_ready():
		_build_path(path)
	# the path may have left the tile layer (mode change, deleted...), cheap enough to always redraw both
	for kind: int in _tile_layers.keys():
		_tiles_dirty[kind] = true
	_bridges_dirty = true


func _build_path(path: PathData) -> void:
	if effective_mode(path) == "tile":
		_centerlines[path.id] = tile_renderer.centerline(path, geometry, path_store.path_seed)
		return # drawn with the other tile paths in _rebuild_tiles
	_centerlines[path.id] = vector_renderer.centerline(path, geometry, path_store.path_seed)
	var node: Node2D = vector_renderer.build(path, geometry, path_store.path_seed)
	if node == null:
		return
	_vector_roots[path.kind].add_child(node)
	_path_nodes[path.id] = node


func _rebuild_tiles(kind: int) -> void:
	if _fallback_nodes.has(kind):
		_fallback_nodes[kind].queue_free()
		_fallback_nodes.erase(kind)
	var layer: TileMapLayer = _tile_layers[kind]
	var index: TerrainMaskIndex = index_for(kind)
	var tile_paths: Array[PathData] = []
	if is_ready() and index != null:
		for path: PathData in path_store.get_all_paths():
			if path.kind == kind and effective_mode(path) == "tile":
				tile_paths.append(path)
	if tile_paths.is_empty():
		layer.clear()
		_missing_tiles[kind] = {}
		tiles_rebuilt.emit()
		return

	_missing_tiles[kind] = tile_renderer.render_layer(layer, tile_paths, index)
	if not _missing_tiles[kind].is_empty():
		var stubs: Node2D = TilePathRenderer.build_stubs(_missing_tiles[kind], geometry, func(path_id: String) -> PathStyle:
			var owner: PathData = path_store.get_path_data(path_id)
			return PathStyles.resolve(owner.style_id, owner.kind))
		_vector_roots[kind].add_child(stubs)
		_fallback_nodes[kind] = stubs
	tiles_rebuilt.emit()


## Puts this node at the z of the anchor layer (it comes after the tilemaps in the tree, so it draws right above it)
## and tells the overhang which layers are ground
func _update_anchor() -> void:
	if GlobalEditorData.user_layers == null:
		return
	var layers: Array[UserLayer] = GlobalEditorData.user_layers.get_all_layers()
	var signature: String = ""
	for layer: UserLayer in layers:
		if is_instance_valid(layer) and is_instance_valid(layer.layer_tilemap_ref):
			signature += "%s:%d;" % [layer.layer_name, layer.layer_tilemap_ref.z_index]
	if signature == _last_layers_signature:
		return
	_last_layers_signature = signature

	var anchor: UserLayer = find_anchor_layer()
	if anchor == null:
		return
	z_index = anchor.layer_tilemap_ref.z_index

	var ground: Array[TileMapLayer] = []
	for layer: UserLayer in layers:
		if is_instance_valid(layer) and is_instance_valid(layer.layer_tilemap_ref) and layer.layer_tilemap_ref.z_index <= z_index:
			ground.append(layer.layer_tilemap_ref)
	ground.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool: return a.z_index < b.z_index)
	ground_layers = ground
	ground_signature = signature + "|" + str(z_index) + "|" + str(geometry.art_offset if geometry else Vector2.ZERO)
	_overhang.configure(ground, geometry)


## The layer named in the store, or the bottom one when it doesnt exist (new map, renamed or deleted layer)
func find_anchor_layer() -> UserLayer:
	var bottom: UserLayer = null
	for layer: UserLayer in GlobalEditorData.user_layers.get_all_layers():
		if not is_instance_valid(layer) or not is_instance_valid(layer.layer_tilemap_ref):
			continue
		if layer.layer_name == path_store.anchor_layer:
			return layer
		if bottom == null or layer.layer_tilemap_ref.z_index < bottom.layer_tilemap_ref.z_index:
			bottom = layer
	return bottom


# --- bridges ---

## - road x river along the edges: a road step between 2 cells crosses the river exactly when the river runs along
##   the edge shared by those 2 cells, so crossings are found by keys (no float intersection)
## - road x river through the centers: they cross in the cells they share (center to center lines never cross
##   anywhere else on a hex grid)
## The bridge is then placed where the drawn lines actually meet
func _rebuild_bridges() -> void:
	var bridges: Array[Dictionary] = []
	if not is_ready():
		_bridges.set_bridges(bridges)
		return

	var river_edges: Dictionary = {} # edge key -> [river path, segment index]
	var river_cells: Dictionary = {} # cell -> [river path, point index]
	var roads: Array[PathData] = []
	for path: PathData in path_store.get_all_paths():
		if path.kind == PathData.Kind.RIVER and path.anchor == PathData.Anchor.VERTEX:
			for i: int in path.points.size() - 1:
				river_edges[_edge_key(path.point_key(i), path.point_key(i + 1))] = [path, i]
		elif path.kind == PathData.Kind.RIVER:
			for i: int in path.points.size():
				river_cells[path.points[i]] = [path, i]
		elif path.anchor == PathData.Anchor.CELL:
			roads.append(path)

	var unit: float = geometry.unit_size()
	for road: PathData in roads:
		var road_style: PathStyle = PathStyles.resolve(road.style_id, road.kind)
		var road_line: PackedVector2Array = get_centerline(road.id)
		for i: int in road.points.size():
			# edge rivers, crossed between point i and i + 1
			if i < road.points.size() - 1:
				var edge: Array = geometry.shared_edge(road.points[i], road.points[i + 1])
				if edge.size() == 2:
					var key: String = _edge_key(HexGeometry.vertex_to_string(edge[0]), HexGeometry.vertex_to_string(edge[1]))
					if river_edges.has(key):
						var guess: Vector2 = (geometry.vertex_position(edge[0]) + geometry.vertex_position(edge[1])) / 2.0
						bridges.append(_make_bridge(road_line, road_style, river_edges[key][0], river_edges[key][1], guess, unit))
			# center rivers, crossed inside a shared cell (only where the road goes through, not where it ends)
			if i > 0 and i < road.points.size() - 1 and river_cells.has(road.points[i]):
				var river_info: Array = river_cells[road.points[i]]
				bridges.append(_make_bridge(road_line, road_style, river_info[0], river_info[1], geometry.cell_center(road.points[i]), unit))
	_bridges.set_bridges(bridges)


func _make_bridge(road_line: PackedVector2Array, road_style: PathStyle, river: PathData, river_index: int, guess: Vector2, unit: float) -> Dictionary:
	var river_style: PathStyle = PathStyles.resolve(river.style_id, river.kind)
	var crossing: Dictionary = _find_crossing(road_line, get_centerline(river.id), guess, unit)
	# river width where it crosses (it grows from source to mouth)
	var progress: float = float(river_index) / maxf(river.points.size() - 1, 1.0)
	var widths: Vector2 = VectorPathRenderer.fill_widths(river_style, unit)
	var river_width: float = lerpf(widths.x, widths.y, progress) + river_style.outline_width * unit * 2.0
	return {
		"position": crossing.position,
		"direction": crossing.direction,
		"length": river_width + road_style.width * unit * 1.5,
		"width": road_style.width * unit * 1.6,
		"style": road_style,
	}


static func _edge_key(key_a: String, key_b: String) -> String:
	return key_a + "#" + key_b if key_a < key_b else key_b + "#" + key_a


## Intersection of 2 polylines closest to [param guess], with the direction of the first line there
static func _find_crossing(road: PackedVector2Array, river: PackedVector2Array, guess: Vector2, unit: float) -> Dictionary:
	var best: Dictionary = {"position": guess, "direction": Vector2.RIGHT}
	var best_distance: float = INF
	var search_radius_squared: float = unit * unit

	# direction fallback: road segment closest to the guess
	for i: int in road.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(guess, road[i], road[i + 1])
		var distance: float = closest.distance_squared_to(guess)
		if distance < best_distance:
			best_distance = distance
			best = {"position": closest, "direction": (road[i + 1] - road[i]).normalized()}

	best_distance = INF
	for i: int in road.size() - 1:
		if Geometry2D.get_closest_point_to_segment(guess, road[i], road[i + 1]).distance_squared_to(guess) > search_radius_squared:
			continue
		for j: int in river.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(road[i], road[i + 1], river[j], river[j + 1])
			if hit == null:
				continue
			var distance: float = (hit as Vector2).distance_squared_to(guess)
			if distance < best_distance:
				best_distance = distance
				best = {"position": hit, "direction": (road[i + 1] - road[i]).normalized()}
	return best


## Draws every bridge, a texture from the road style or a simple wooden deck
class BridgesDrawer extends Node2D:
	var _bridges: Array[Dictionary] = []

	func set_bridges(bridges: Array[Dictionary]) -> void:
		_bridges = bridges
		queue_redraw()

	func get_bridges() -> Array[Dictionary]:
		return _bridges

	func _draw() -> void:
		for bridge: Dictionary in _bridges:
			var style: PathStyle = bridge.style
			var length: float = bridge.length
			var width: float = bridge.width
			var direction: Vector2 = bridge.direction
			draw_set_transform(bridge.position, direction.angle())
			var deck: Rect2 = Rect2(-length / 2.0, -width / 2.0, length, width)
			if style.bridge_texture != null:
				draw_texture_rect(style.bridge_texture, deck, false)
				continue
			var dark: Color = style.bridge_color.darkened(0.55)
			draw_rect(deck.grow(width * 0.08), dark)
			draw_rect(deck, style.bridge_color)
			var planks: int = maxi(int(length / (width * 0.35)), 3)
			for i: int in range(1, planks):
				var x: float = -length / 2.0 + length * i / planks
				draw_line(Vector2(x, -width / 2.0), Vector2(x, width / 2.0), dark, maxf(width * 0.05, 0.5), true)
			# rails
			for side: float in [-1.0, 1.0]:
				var y: float = side * width / 2.0
				draw_line(Vector2(-length / 2.0 - width * 0.15, y), Vector2(length / 2.0 + width * 0.15, y), dark, maxf(width * 0.14, 1.0), true)
		draw_set_transform(Vector2.ZERO)
