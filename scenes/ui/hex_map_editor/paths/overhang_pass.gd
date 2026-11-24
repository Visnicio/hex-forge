## Redraws, on top of the paths, only the art of tall tiles that sticks out above their own hex.[br]
## Tiles taller than the hex (e.g. David Baumgart's 256x384 mountains) overlap the row behind them; if paths were
## simply drawn above the ground layers they would cover those mountain peaks. Instead of y-sorting (which wouldnt
## work with the ground rendered to a SubViewport in phase 3), the ground is drawn as usual, then the paths, then
## this pass: a mirror of the ground layers with a shader that keeps only the overhanging pixels.[br]
## Only tiles that actually have art above their hex are mirrored (found by scanning the atlas once per tileset)
class_name OverhangPass extends Node2D

const OVERHANG_SHADER: Shader = preload("res://resources/shaders/tile_overhang.gdshader")
## How much the hex is enlarged when deciding what is "outside", so the hex outline isnt redrawn over paths
const HEX_TOLERANCE: float = 0.06
## Minimum opaque samples outside the hex to count a tile as tall (ignores stray antialiased pixels)
const MIN_OVERHANG_SAMPLES: int = 4

var _ground_layers: Array[TileMapLayer] = []
var _geometry: HexGeometry
var _dirty: bool = false

## Analysis of the current tileset: source_id -> {atlas_coords: true} for tiles with overhang
var _overhang_tiles: Dictionary[int, Dictionary] = {}
var _materials: Dictionary[int, ShaderMaterial] = {}
var _analyzed_key: String = ""


func _ready() -> void:
	SignalBus.map_cells_changed.connect(mark_dirty)


## Called when the tileset, the art offset or the layers below the paths change.[br]
## [param ground_layers] must be sorted from the bottom layer to the top one
func configure(ground_layers: Array[TileMapLayer], geometry: HexGeometry) -> void:
	_ground_layers = ground_layers
	_geometry = geometry
	if geometry != null and geometry.is_valid():
		var key: String = "%d|%s" % [geometry.layer.tile_set.get_instance_id(), geometry.art_offset]
		if key != _analyzed_key:
			_analyzed_key = key
			_analyze_tileset(geometry)
	mark_dirty()


func mark_dirty() -> void:
	_dirty = true


## True when this tile has art sticking out above its hex (and so gets redrawn by this pass)
func is_tall(source_id: int, atlas_coords: Vector2i) -> bool:
	return _overhang_tiles.has(source_id) and _overhang_tiles[source_id].has(atlas_coords)


## True when the current tileset has any tile taller than its hex (false for flat tilesets, the pass does nothing)
func has_overhang_tiles() -> bool:
	for tiles: Dictionary in _overhang_tiles.values():
		if not tiles.is_empty():
			return true
	return false


# painting fires map_cells_changed for every cell, so the mirrors are rebuilt at most once per frame
func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild_mirrors()


func _rebuild_mirrors() -> void:
	for child: Node in get_children():
		child.queue_free()

	if _geometry == null or not _geometry.is_valid() or not has_overhang_tiles():
		return

	# every mirror stays above the paths (same z as this node), lower ground layers first so they keep their order;
	# one mirror per source, since the shader needs the region size of the atlas it reads from
	for ground: TileMapLayer in _ground_layers:
		if not is_instance_valid(ground):
			continue
		for source_id: int in _overhang_tiles.keys():
			var tall_tiles: Dictionary = _overhang_tiles[source_id]
			if tall_tiles.is_empty():
				continue
			var mirror: TileMapLayer = null
			for cell: Vector2i in ground.get_used_cells():
				if ground.get_cell_source_id(cell) != source_id:
					continue
				var atlas_coords: Vector2i = ground.get_cell_atlas_coords(cell)
				if not tall_tiles.has(atlas_coords):
					continue
				if mirror == null:
					mirror = TileMapLayer.new()
					mirror.tile_set = ground.tile_set
					mirror.material = _materials[source_id]
					# front rows over back rows, in case some art sticks out more than one row
					mirror.y_sort_enabled = true
					add_child(mirror)
				mirror.set_cell(cell, source_id, atlas_coords, ground.get_cell_alternative_tile(cell))


func _analyze_tileset(geometry: HexGeometry) -> void:
	_overhang_tiles.clear()
	_materials.clear()
	var tile_set: TileSet = geometry.layer.tile_set
	var corners: PackedVector2Array = geometry.corner_offsets()
	for i: int in corners.size():
		corners[i] *= 1.0 + HEX_TOLERANCE

	for source_index: int in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(source_index)
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null or source.get_tiles_count() == 0:
			continue

		var region_size: Vector2 = Vector2(source.texture_region_size)
		# only tiles taller than the hex can stick out of it
		if region_size.y <= float(tile_set.tile_size.y):
			_overhang_tiles[source_id] = {}
			continue

		var first_origin: Vector2 = Vector2(source.get_tile_data(source.get_tile_id(0), 0).texture_origin)
		var hex_center: Vector2 = region_size / 2.0 + geometry.art_offset + first_origin

		var image: Image = source.texture.get_image()
		if image == null:
			push_warning("OverhangPass - couldnt read the atlas of source %d, tall art will be covered by paths" % source_id)
			_overhang_tiles[source_id] = {}
			continue
		if image.is_compressed():
			image.decompress()

		var tall: Dictionary = {}
		for tile_index: int in source.get_tiles_count():
			var atlas_coords: Vector2i = source.get_tile_id(tile_index)
			var region: Rect2i = source.get_tile_texture_region(atlas_coords)
			if _has_overhang(image, region, hex_center, corners):
				tall[atlas_coords] = true
		_overhang_tiles[source_id] = tall

		_materials[source_id] = make_material(source, geometry, true)


## Material that keeps only the art above the hex ([param keep_overhang]) or only the hex and its base,
## for the tiles of [param source]. Returns null when the source tiles arent taller than the hex
## How much bigger the hex is when cutting the peaks OFF for the biome smoothing: hand painted hexes often spill a bit
## past the exact hex shape and that spill is what closes the seams between tiles, only clear overhang is removed
const HEX_ONLY_TOLERANCE: float = 0.25


static func make_material(source: TileSetAtlasSource, geometry: HexGeometry, keep_overhang: bool) -> ShaderMaterial:
	if source == null or source.texture == null or source.get_tiles_count() == 0:
		return null
	var region_size: Vector2 = Vector2(source.texture_region_size)
	if region_size.y <= float(geometry.layer.tile_set.tile_size.y):
		return null
	var corners: PackedVector2Array = geometry.corner_offsets()
	for i: int in corners.size():
		corners[i] *= 1.0 + (HEX_TOLERANCE if keep_overhang else HEX_ONLY_TOLERANCE)
	var first_origin: Vector2 = Vector2(source.get_tile_data(source.get_tile_id(0), 0).texture_origin)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = OVERHANG_SHADER
	material.set_shader_parameter("keep_overhang", keep_overhang)
	material.set_shader_parameter("atlas_size", Vector2(source.texture.get_size()))
	material.set_shader_parameter("region_size", region_size)
	material.set_shader_parameter("margins", Vector2(source.margins))
	material.set_shader_parameter("separation", Vector2(source.separation))
	material.set_shader_parameter("hex_center", region_size / 2.0 + geometry.art_offset + first_origin)
	material.set_shader_parameter("corners", corners)
	return material


## Samples the upper half of the tile region looking for opaque pixels outside the hex
static func _has_overhang(image: Image, region: Rect2i, hex_center: Vector2, corners: PackedVector2Array) -> bool:
	var stride: int = maxi(region.size.x / 48, 1)
	var found: int = 0
	var bottom: int = mini(int(hex_center.y), region.size.y)
	for y: int in range(0, bottom, stride):
		for x: int in range(0, region.size.x, stride):
			var pixel: Vector2i = region.position + Vector2i(x, y)
			if pixel.x >= image.get_width() or pixel.y >= image.get_height():
				continue
			if image.get_pixelv(pixel).a < 0.5:
				continue
			if not Geometry2D.is_point_in_polygon(Vector2(x, y) - hex_center, corners):
				found += 1
				if found >= MIN_OVERHANG_SAMPLES:
					return true
	return false
