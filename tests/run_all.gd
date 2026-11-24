## Headless tests for map data, save migration and hex geometry.[br]
## Runs as a scene (not with --script) so the autoloads exist, from the project folder:[br]
## [code]godot --headless --path . res://tests/run_all.tscn[/code] (exit code 1 on failure)[br]
## Extra saves (e.g. your own maps, not committed) can be checked with
## [code]HEXFORGE_EXTRA_SAVES=/path/to/folder[/code], every .json in it must load
extends Node

const TILESETS: Array[String] = [
	"res://samples/david_baumgart_packed_sample.tres", # pointy-top, tall tiles
	"res://samples/pixel_fantasy_sample.tres", # flat-top
]

var _failures: int = 0
var _checks: int = 0
var _current: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root: Window = get_tree().root
	for config_path: String in TILESETS:
		var config: MapTilesetConfiguration = load(config_path)
		var layer: TileMapLayer = TileMapLayer.new()
		layer.tile_set = config.tileset_resource
		root.add_child(layer)
		var geometry: HexGeometry = HexGeometry.new(layer, config)
		_section("_test_geometry", _test_geometry(config.tileset_name, geometry))
		_section("_test_meander", _test_meander(config.tileset_name, geometry))
		_section("_test_overhang", _test_overhang(config.tileset_name, geometry))
		layer.queue_free()

	_section("_test_art_offsets", _test_art_offsets())
	_section("_test_path_data_round_trip", _test_path_data_round_trip())
	_section("_test_map_round_trip", _test_map_round_trip())
	_section("_test_migration_fixture", _test_migration_fixture("res://tests/fixtures/alpha_0_3_map.json"))
	_section("_test_newer_format", _test_newer_format())
	_section("_test_extra_saves", _test_extra_saves())
	_section("_test_terrain_index", _test_terrain_index())
	_section("_test_tile_renderer", _test_tile_renderer())
	_section("_test_old_mod_pack", _test_old_mod_pack())
	_section("_test_tile_colors", _test_tile_colors())
	_section("_test_edge_mask", _test_edge_mask())
	_section("_test_mod_template", _test_mod_template())
	_section("_test_lint_samples", _test_lint_samples())

	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A script error inside a test makes it return null instead of true, which would otherwise go unnoticed
func _section(section_name: String, finished: Variant) -> void:
	_current = section_name
	check(finished == true, "section ran to the end (no script error)")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, message])


func _test_geometry(tileset_name: String, geometry: HexGeometry) -> bool:
	_current = "geometry " + tileset_name
	var cell: Vector2i = Vector2i(3, 3)
	var around: Array = geometry.neighbors(cell)
	check(around.size() == 6, "6 neighbors")

	var corners: PackedVector2Array = geometry.corners(cell)
	check(corners.size() == 6, "6 corners")
	var center: Vector2 = geometry.cell_center(cell)
	var sum: Vector2 = Vector2.ZERO
	for corner: Vector2 in corners:
		sum += corner
	check((sum / 6.0).distance_to(center) < 0.01, "corners are centered on the cell")
	check(geometry.cell_at(center) == cell, "cell_at(cell_center) is the same cell (with art offset)")

	# every corner is shared by exactly 3 cells and is the same point seen from each of them
	for vertex: Array in geometry.cell_vertices(cell):
		check(geometry.is_vertex_valid(vertex), "corner trio is mutually adjacent")
		check(geometry.vertex_neighbors(vertex).size() == 3, "a corner has 3 edges")
		for other: Vector2i in vertex:
			check(geometry.cell_vertices(other).has(vertex), "corner %s is also a corner of %s" % [vertex, other])

	# the edge between 2 neighbors is 2 corners at hex side length from each other
	var edge: Array = geometry.shared_edge(cell, around[0])
	check(edge.size() == 2, "shared edge has 2 corners")
	check(geometry.are_vertices_adjacent(edge[0], edge[1]), "corners of an edge are adjacent")
	check(geometry.shared_edge(cell, Vector2i(cell.x + 5, cell.y + 5)).is_empty(), "no shared edge between far cells")

	var nearest: Array = geometry.nearest_vertex(corners[2] + Vector2(0.5, 0.5))
	check(nearest == geometry.cell_vertices(cell)[2], "nearest_vertex finds the corner under the mouse")

	var route: Array = geometry.cell_route(cell, Vector2i(cell.x + 4, cell.y - 1))
	var previous: Vector2i = cell
	var connected: bool = not route.is_empty()
	for step: Vector2i in route:
		connected = connected and geometry.are_adjacent(previous, step)
		previous = step
	check(connected and previous == Vector2i(cell.x + 4, cell.y - 1), "cell_route is a chain of neighbors reaching the target")

	var start_vertex: Array = geometry.cell_vertices(cell)[0]
	var end_vertex: Array = geometry.cell_vertices(Vector2i(cell.x + 2, cell.y + 1))[3]
	var vertex_steps: Array = geometry.vertex_route(start_vertex, end_vertex)
	var last_vertex: Array = start_vertex
	var vertex_connected: bool = not vertex_steps.is_empty()
	for step: Array in vertex_steps:
		vertex_connected = vertex_connected and geometry.are_vertices_adjacent(last_vertex, step)
		last_vertex = step
	check(vertex_connected and last_vertex == end_vertex, "vertex_route is a chain of edges reaching the target")

	# vertex ids survive the save format
	var as_string: String = HexGeometry.vertex_to_string(start_vertex)
	check(HexGeometry.vertex_from_string(as_string) == start_vertex, "vertex string round trip")
	check(HexGeometry.make_vertex(start_vertex[2], start_vertex[0], start_vertex[1]) == start_vertex, "vertex id ignores argument order")
	return true


func _test_meander(tileset_name: String, geometry: HexGeometry) -> bool:
	_current = "meander " + tileset_name
	var style: PathStyle = PathStyles.resolve("builtin:river", PathData.Kind.RIVER)
	var a: Vector2 = Vector2(0, 0)
	var b: Vector2 = Vector2(100, 20)
	var forward: PackedVector2Array = VectorPathRenderer.meander_segment(a, b, "k1", "k2", style, 42)
	var backward: PackedVector2Array = VectorPathRenderer.meander_segment(b, a, "k2", "k1", style, 42)
	backward.reverse()
	check(forward == backward, "a segment has the same shape in both directions")
	check(forward != VectorPathRenderer.meander_segment(a, b, "k1", "k2", style, 43), "another seed gives another shape")

	# extending a road only changes the end of the drawn line, not the start
	var road: PathData = PathData.create(PathData.Kind.ROAD, PathData.Anchor.CELL)
	road.points = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var renderer: VectorPathRenderer = VectorPathRenderer.new()
	var before: PackedVector2Array = renderer.centerline(road, geometry, 7)
	road.points.append(geometry.neighbors(Vector2i(3, 0))[0])
	var after: PackedVector2Array = renderer.centerline(road, geometry, 7)
	var same_prefix: int = 0
	while same_prefix < before.size() and same_prefix < after.size() and before[same_prefix].is_equal_approx(after[same_prefix]):
		same_prefix += 1
	check(same_prefix > before.size() / 2, "extending keeps the start of the line (%d/%d points equal)" % [same_prefix, before.size()])
	return true


func _test_overhang(tileset_name: String, geometry: HexGeometry) -> bool:
	_current = "overhang " + tileset_name
	var overhang: OverhangPass = OverhangPass.new()
	add_child(overhang)
	overhang.configure([], geometry)
	if tileset_name.contains("David"):
		check(overhang._overhang_tiles[0].has(Vector2i(6, 1)), "snowy mountain (6,1) sticks out of its hex")
		check(overhang._overhang_tiles[0].has(Vector2i(3, 2)), "castle (3,2) sticks out of its hex")
		check(not overhang._overhang_tiles[0].has(Vector2i(1, 0)), "dirt (1,0) is flat")
	else:
		check(not overhang._overhang_tiles[0].has(Vector2i(0, 0)), "plain grass (0,0) is flat")
		check(overhang._overhang_tiles[0].has(Vector2i(12, 2)), "mountain (12,2) sticks out of its hex")
	print("  %s: %d tall tiles" % [tileset_name, overhang._overhang_tiles.get(0, {}).size()])
	overhang.queue_free()
	return true


func _test_art_offsets() -> bool:
	_current = "art offset"
	var david: MapTilesetConfiguration = load("res://samples/david_baumgart_packed_sample.tres")
	check(david.auto_hex_art_offset, "configs without the new fields default to auto (old mods keep working)")
	check(HexGeometry.compute_art_offset(david.tileset_resource, david) == Vector2(0, 64), "David auto offset is 64px down")
	var pixel: MapTilesetConfiguration = load("res://samples/pixel_fantasy_sample.tres")
	check(HexGeometry.compute_art_offset(pixel.tileset_resource, pixel) == Vector2(0, 8), "pixel sample uses its override")
	return true


func _test_path_data_round_trip() -> bool:
	_current = "path data"
	var river: PathData = PathData.create(PathData.Kind.RIVER, PathData.Anchor.VERTEX)
	river.path_name = "Rio Lento"
	river.description = "Ação, acentos e \"aspas\""
	river.points = [HexGeometry.make_vertex(Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)), HexGeometry.make_vertex(Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1))]
	var restored: PathData = PathData.from_dict(JSON.parse_string(JSON.stringify(PathData.to_dict(river))))
	check(restored != null and restored.same_as(river), "vertex path survives JSON")
	check(restored.points[0] is Array and restored.points[0][0] is Vector2i, "vertex points come back as Vector2i trios")

	var road: PathData = PathData.create(PathData.Kind.ROAD, PathData.Anchor.CELL)
	road.points = [Vector2i(-3, 2), Vector2i(-2, 2)]
	restored = PathData.from_dict(JSON.parse_string(JSON.stringify(PathData.to_dict(road))))
	check(restored.same_as(road) and restored.points[1] is Vector2i, "cell path survives JSON")

	var broken: PathData = PathData.from_dict({"kind": "river", "points": ["nope", "(1, 2)|(2, 2)|(1, 3)"], "style_id": "some_mod:gone"})
	check(broken.anchor == PathData.Anchor.VERTEX and broken.points.size() == 1, "invalid points are skipped, rivers default to edges")
	check(PathStyles.resolve(broken.style_id, broken.kind).id == "builtin:river", "unknown style falls back to the default of the kind")
	return true


func _test_map_round_trip() -> bool:
	_current = "map round trip"
	var map_data: MapData = MapData.new()
	map_data.map_name = "Round trip"
	map_data.manifest_version = "Alpha 0.4"
	map_data.path_seed = 1234
	map_data.path_anchor_layer = "World"
	var road: PathData = PathData.create(PathData.Kind.ROAD, PathData.Anchor.CELL)
	road.points = [Vector2i(0, 0), Vector2i(1, 0)]
	map_data.paths[road.id] = road

	var json: String = JSON.stringify(MapData.to_dict(map_data), "\t")
	var loaded: MapData = MapData.from_dict(JSON.parse_string(json))
	check(loaded.format_version == MapMigrations.CURRENT_FORMAT_VERSION, "saved with current format version")
	check(loaded.paths.size() == 1 and loaded.paths[road.id].same_as(road), "paths survive")
	check(loaded.path_seed == 1234 and loaded.path_anchor_layer == "World", "path settings survive")
	return true


func _test_migration_fixture(path: String) -> bool:
	_current = "migration " + path.get_file()
	var raw: Dictionary = _read_json(path)
	check(not raw.is_empty(), "fixture readable")
	check(not raw.has("format_version"), "fixture is a format 1 save")
	var loaded: MapData = MapData.from_dict(raw)
	check(loaded.format_version == 1, "detected as format 1")
	check(loaded.paths.is_empty(), "old maps have no paths")
	check(loaded.layers.size() == 2 and loaded.layers[&"World"].cells.size() == 4, "layers still load")
	check(loaded.markers.size() == 1 and loaded.hexes_data.size() == 1, "markers and hex data still load")
	check(loaded.map_tileset_configuration != null, "tileset config still loads")

	var resaved: Dictionary = JSON.parse_string(JSON.stringify(MapData.to_dict(loaded)))
	check(int(resaved.format_version) == MapMigrations.CURRENT_FORMAT_VERSION and resaved.has("paths"), "resaving upgrades the format")
	var reloaded: MapData = MapData.from_dict(resaved)
	check(reloaded.layers[&"World"].cells == loaded.layers[&"World"].cells, "cells identical after upgrade")
	check(reloaded.path_seed == loaded.path_seed, "seed given on migration is kept")
	return true


func _test_newer_format() -> bool:
	_current = "newer format"
	var raw: Dictionary = _read_json("res://tests/fixtures/alpha_0_3_map.json")
	raw["format_version"] = 99
	raw["some_future_thing"] = {"a": 1}
	var loaded: MapData = MapData.from_dict(raw)
	check(loaded.format_version == 99, "newer format is reported so the editor can warn")
	check(loaded.layers.size() == 2, "known data of a newer save still loads")
	return true


func _test_extra_saves() -> bool:
	var folder: String = OS.get_environment("HEXFORGE_EXTRA_SAVES")
	if folder.is_empty():
		return true
	for file_name: String in DirAccess.get_files_at(folder):
		if not file_name.ends_with(".json"):
			continue
		_current = "extra save " + file_name
		var raw: Dictionary = _read_json(folder.path_join(file_name))
		var loaded: MapData = MapData.from_dict(raw)
		var resaved: MapData = MapData.from_dict(JSON.parse_string(JSON.stringify(MapData.to_dict(loaded))))
		var total_cells: int = 0
		var same: bool = loaded.layers.size() == resaved.layers.size()
		for layer_name: StringName in loaded.layers.keys():
			total_cells += loaded.layers[layer_name].cells.size()
			same = same and resaved.layers.has(layer_name) and resaved.layers[layer_name].cells == loaded.layers[layer_name].cells
		check(same, "layers identical after load + save + load")
		check(resaved.markers.size() == loaded.markers.size() and resaved.hexes_data.size() == loaded.hexes_data.size(), "markers and hexes kept")
		print("  %s: %d cells, %d markers, %d hexes, format %d" % [file_name, total_cells, loaded.markers.size(), loaded.hexes_data.size(), loaded.format_version])
	return true


func _read_json(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _test_terrain_index() -> bool:
	_current = "terrain index"
	var pixel: MapTilesetConfiguration = load("res://samples/pixel_fantasy_sample.tres")
	var roads: TerrainMaskIndex = TerrainMaskIndex.build(pixel.tileset_resource, pixel.road_terrain_set, pixel.road_terrain)
	check(roads != null and roads.sides.size() == 6, "pixel sample declares road tiles on 6 hex sides")
	check(roads.coverage() == Vector2i(11, 63), "11 road combinations of 63 (got %s)" % roads.coverage())
	check(TerrainMaskIndex.build(pixel.tileset_resource, pixel.river_terrain_set, pixel.river_terrain) == null, "pixel sample has no river tiles")
	check(not pixel.provides_river_tiles() and pixel.provides_road_tiles(), "provides_path_tiles per kind")

	var david: MapTilesetConfiguration = load("res://samples/david_baumgart_packed_sample.tres")
	var rivers: TerrainMaskIndex = TerrainMaskIndex.build(david.tileset_resource, david.river_terrain_set, david.river_terrain)
	check(rivers != null and rivers.coverage() == Vector2i(10, 63), "David rivers cover 10 combinations with the mirrored tiles (got %s)" % (rivers.coverage() if rivers else "null"))
	check(TerrainMaskIndex.build(david.tileset_resource, 7, 0) == null, "a terrain set that doesnt exist falls back to vector instead of crashing")
	return true


func _test_tile_renderer() -> bool:
	_current = "tile renderer"
	var pixel: MapTilesetConfiguration = load("res://samples/pixel_fantasy_sample.tres")
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = pixel.tileset_resource
	add_child(layer)
	var geometry: HexGeometry = HexGeometry.new(layer, pixel)
	var index: TerrainMaskIndex = TerrainMaskIndex.build(pixel.tileset_resource, 0, 0)

	# zig-zag through diagonal sides only (top-right, bottom-right, ...) has a tile everywhere but at the 2 ends
	var start: Vector2i = Vector2i(5, 5)
	var top_right: Vector2i = layer.get_neighbor_cell(start, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	var then_bottom_right: Vector2i = layer.get_neighbor_cell(top_right, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	var then_top_right: Vector2i = layer.get_neighbor_cell(then_bottom_right, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	var road: PathData = PathData.create(PathData.Kind.ROAD, PathData.Anchor.CELL)
	road.points = [start, top_right, then_bottom_right, then_top_right]
	var missing: Dictionary = TilePathRenderer.new().render_layer(layer, [road], index)
	check(missing.size() == 2 and missing.has(start) and missing.has(then_top_right), "only the 2 dead ends have no tile (got %s)" % [missing.keys()])
	check(layer.get_cell_atlas_coords(top_right) == Vector2i(5, 9), "bottom-left + bottom-right uses tile (5, 9)")
	check(layer.get_cell_atlas_coords(then_bottom_right) == Vector2i(6, 9), "top-left + top-right uses tile (6, 9)")

	# a straight vertical step has no tile in this tileset
	var up: Vector2i = layer.get_neighbor_cell(start, TileSet.CELL_NEIGHBOR_TOP_SIDE)
	road.points = [layer.get_neighbor_cell(start, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE), start, up]
	missing = TilePathRenderer.new().render_layer(layer, [road], index)
	check(missing.has(start) and missing[start].mask != 0, "bottom-left + top has no tile, reported with its sides")

	# exceptions: a tile picked by hand and a hex forced to vector
	road.tile_exceptions[str(start)] = TilePathRenderer.tile_exception(index.entries()[0])
	road.tile_exceptions[str(up)] = {"vector": true}
	var restored: PathData = PathData.from_dict(JSON.parse_string(JSON.stringify(PathData.to_dict(road))))
	missing = TilePathRenderer.new().render_layer(layer, [restored], index)
	check(layer.get_cell_atlas_coords(start) == index.entries()[0].atlas_coords, "tile picked by hand survives JSON and is used")
	check(missing.has(up) and missing[up].forced, "hex forced to vector is reported as forced")

	var stubs: Node2D = TilePathRenderer.build_stubs(missing, geometry, func(_id: String) -> PathStyle: return PathStyles.resolve("", PathData.Kind.ROAD))
	check(stubs.get_child_count() > 0, "vector stubs built for the hexes without tile")
	stubs.free()
	layer.queue_free()
	return true


## A mod made before roads existed: its config has none of the new fields
func _test_old_mod_pack() -> bool:
	_current = "old mod pck"
	var folder: String = OS.get_environment("HEXFORGE_TEST_TMP")
	if folder.is_empty():
		folder = OS.get_user_data_dir().path_join("test_tmp")
	DirAccess.make_dir_recursive_absolute(folder)
	var config_text: String = """[gd_resource type="Resource" script_class="MapTilesetConfiguration" format=3]

[ext_resource type="Script" path="res://resources/definitions/tilesets/map_tileset_configuration.gd" id="1"]
[ext_resource type="TileSet" path="res://resources/tilesets/example_tileset.tres" id="2"]

[resource]
script = ExtResource("1")
tileset_name = "Old Mod"
tileset_resource = ExtResource("2")
tilemap_scale = 1.5
"""
	var info_text: String = """[gd_resource type="Resource" script_class="ModInfoResource" format=3]

[ext_resource type="Script" path="res://resources/definitions/modding/mod_info_resource.gd" id="1"]
[ext_resource type="Resource" path="res://old_test_mod/config.tres" id="2"]

[resource]
script = ExtResource("1")
author = "test"
mod_name = "Old Mod"
mod_configuration = ExtResource("2")
"""
	_write(folder.path_join("config.tres"), config_text)
	_write(folder.path_join("mod_info.tres"), info_text)
	var pck_path: String = folder.path_join("old_test_mod.pck")
	var packer: PCKPacker = PCKPacker.new()
	packer.pck_start(pck_path)
	packer.add_file("res://old_test_mod/config.tres", folder.path_join("config.tres"))
	packer.add_file("res://old_test_mod/mod_info.tres", folder.path_join("mod_info.tres"))
	packer.flush()

	# same steps as ModLoader
	check(ProjectSettings.load_resource_pack(pck_path), "old mod pck loads")
	var mod_info: ModInfoResource = load("res://old_test_mod/mod_info.tres") as ModInfoResource
	check(mod_info != null and mod_info.mod_configuration != null, "mod_info and its config load")
	var config: MapTilesetConfiguration = mod_info.mod_configuration
	check(config.tileset_name == "Old Mod" and is_equal_approx(config.tilemap_scale, 1.5), "old fields keep their values")
	check(config.road_terrain_set == -1 and config.river_terrain == -1 and config.path_styles.is_empty(), "new fields default to 'not provided'")
	check(config.auto_hex_art_offset, "art offset defaults to automatic")
	check(not config.provides_road_tiles(), "old mod draws roads in vector even if its tileset had terrains")

	for file_name: String in ["config.tres", "mod_info.tres", "old_test_mod.pck"]:
		DirAccess.remove_absolute(folder.path_join(file_name))
	return true


static func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_tile_colors() -> bool:
	_current = "tile colors"
	var david: TileSet = load("res://resources/tilesets/david_baumgart_packed.tres")
	check(TileColorCache.is_water(david, 0, Vector2i(5, 1)), "David ocean (5,1) is water")
	check(TileColorCache.is_water(david, 0, Vector2i(3, 3)), "David calm ocean (3,3) is water")
	check(not TileColorCache.is_water(david, 0, Vector2i(4, 0)), "David hills (4,0) are land")
	check(not TileColorCache.is_water(david, 0, Vector2i(4, 4)), "David snow field (4,4) is not water")
	check(not TileColorCache.is_water(david, 0, Vector2i(3, 0)), "David marsh (3,0) is not water")
	var pixel: TileSet = load("res://resources/tilesets/example_tileset.tres")
	check(TileColorCache.is_water(pixel, 0, Vector2i(0, 5)), "pixel water (0,5) is water")
	check(not TileColorCache.is_water(pixel, 0, Vector2i(0, 0)), "pixel grass (0,0) is land")
	check(not TileColorCache.is_water(pixel, 0, Vector2i(5, 3)), "pixel snow (5,3) is not water")
	var grass: Color = TileColorCache.average_color(pixel, 0, Vector2i(0, 0))
	check(grass.g > grass.r and grass.g > grass.b, "grass average color is green (%s)" % grass)

	# custom data wins over the guess
	var custom: TileSet = pixel.duplicate(true)
	custom.add_custom_data_layer()
	custom.set_custom_data_layer_name(0, TileColorCache.LAYER_IS_WATER)
	custom.set_custom_data_layer_type(0, TYPE_BOOL)
	(custom.get_source(0) as TileSetAtlasSource).get_tile_data(Vector2i(0, 0), 0).set_custom_data(TileColorCache.LAYER_IS_WATER, true)
	check(TileColorCache.is_water(custom, 0, Vector2i(0, 0)), "is_water custom data overrides the color guess")
	return true


func _test_edge_mask() -> bool:
	for config_path: String in TILESETS:
		var config: MapTilesetConfiguration = load(config_path)
		_current = "edge mask " + config.tileset_name
		var layer: TileMapLayer = TileMapLayer.new()
		layer.tile_set = config.tileset_resource
		add_child(layer)
		var geometry: HexGeometry = HexGeometry.new(layer, config)
		var mask_set: TileSet = EdgeMaskTileset.build(geometry)
		check(mask_set.tile_shape == config.tileset_resource.tile_shape and mask_set.tile_offset_axis == config.tileset_resource.tile_offset_axis \
			and mask_set.tile_layout == config.tileset_resource.tile_layout and mask_set.tile_size == config.tileset_resource.tile_size, "ghost tileset copies shape, layout, axis and size")
		var image: Image = (mask_set.get_source(0) as TileSetAtlasSource).texture.get_image()
		var center: Vector2i = image.get_size() / 2
		check(image.get_pixelv(center).r > 0.9, "mask is ~1 in the center")
		var corner: Vector2 = geometry.corner_offsets()[0] * 0.97 + Vector2(center)
		check(image.get_pixelv(Vector2i(corner)).r < 0.15, "mask is ~0 near a corner")
		check(image.get_pixel(0, 0).a == 0.0, "mask is empty outside the hex")
		layer.queue_free()
	return true


## The template ships copies of the definition scripts, they must not drift from the game's
## (set HEXFORGE_TEMPLATE_PCK to a pck exported from templates/mod_template to also load it like ModLoader does)
func _test_mod_template() -> bool:
	_current = "mod template"
	var template_dir: String = ProjectSettings.globalize_path("res://templates/mod_template")
	for definition: String in ["resources/definitions/tilesets/map_tileset_configuration.gd",
			"resources/definitions/modding/mod_info_resource.gd", "resources/definitions/paths/path_style.gd"]:
		check(FileAccess.get_file_as_string("res://" + definition) == FileAccess.get_file_as_string(template_dir.path_join(definition)),
			"template copy of %s matches the game (rerun tools/build_mod_template.gd)" % definition.get_file())

	var pck_path: String = OS.get_environment("HEXFORGE_TEMPLATE_PCK")
	if pck_path.is_empty():
		return true
	check(ProjectSettings.load_resource_pack(pck_path), "template pck loads")
	var mod_info: ModInfoResource = load("res://my_tileset/mod_info.tres") as ModInfoResource
	check(mod_info != null and mod_info.mod_configuration != null, "template mod_info and config load")
	if mod_info == null:
		return true
	var rows: Array[Dictionary] = ModLint.inspect(mod_info.mod_configuration)
	for row: Dictionary in rows:
		print("  template lint: %-32s %-8s %s" % [row.feature, row.status, row.detail])
		check(row.status != ModLint.ERROR, "template has no problem in '%s'" % row.feature)
	var by_feature: Dictionary = {}
	for row: Dictionary in rows:
		by_feature[row.feature] = row.status
	for feature: String in ["Water (is_water)", "Blend color (blend_color)", "Biome (biome)", "Path styles"]:
		check(by_feature.get(feature) == ModLint.OK, "template provides %s" % feature)
	var roads: TerrainMaskIndex = TerrainMaskIndex.build(mod_info.mod_configuration.tileset_resource, 0, 0)
	check(roads != null and roads.has_mask(roads.mask_for(_probe_layer(roads.tile_set), Vector2i(4, 4), {_probe_layer(roads.tile_set).get_neighbor_cell(Vector2i(4, 4), TileSet.CELL_NEIGHBOR_LEFT_SIDE): true, _probe_layer(roads.tile_set).get_neighbor_cell(Vector2i(4, 4), TileSet.CELL_NEIGHBOR_RIGHT_SIDE): true})),
		"template has a left-right road tile")
	return true


func _probe_layer(tile_set: TileSet) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = tile_set
	add_child(layer)
	layer.queue_free()
	return layer


func _test_lint_samples() -> bool:
	for config_path: String in TILESETS:
		var config: MapTilesetConfiguration = load(config_path)
		_current = "lint " + config.tileset_name
		var rows: Array[Dictionary] = ModLint.inspect(config)
		check(rows.size() >= 8, "lint lists every feature")
		for row: Dictionary in rows:
			print("  %s lint: %-32s %-8s %s" % [config.tileset_name, row.feature, row.status, row.detail])
			check(row.status != ModLint.ERROR, "no problem in '%s'" % row.feature)
	_current = "lint broken config"
	var broken: MapTilesetConfiguration = MapTilesetConfiguration.new()
	check(ModLint.inspect(broken)[0].status == ModLint.ERROR, "empty config is reported, not crashing")
	return true
