## End to end check of the road/river tools inside the real editor scene, on both sample tilesets.[br]
## The editor runs inside a SubViewport so mouse events can be pushed without moving the real cursor.[br]
## Needs a display (it renders screenshots), from the project folder:[br]
## [code]E2E_OUT=/some/folder godot --path . res://tests/e2e_paths.tscn[/code] (exit code 1 on failure)
extends Node

const EDITOR_SCENE: PackedScene = preload("res://scenes/ui/hex_map_editor/hex_map_editor.tscn")
const CASES: Array[Dictionary] = [
	{"config": "res://samples/david_baumgart_packed_sample.tres", "ground": Vector2i(7, 0), "tall": Vector2i(6, 1), "water": Vector2i(5, 1), "other": Vector2i(2, 0), "zoom": 1.6},
	{"config": "res://samples/pixel_fantasy_sample.tres", "ground": Vector2i(0, 0), "tall": Vector2i(12, 2), "water": Vector2i(0, 5), "other": Vector2i(0, 2), "zoom": 2.8},
]

var _out_dir: String
var _viewport: SubViewport
var _editor: HexMapEditor
var _checks: int = 0
var _failures: int = 0
var _current: String = ""


func _ready() -> void:
	_out_dir = OS.get_environment("E2E_OUT")
	if _out_dir.is_empty():
		_out_dir = OS.get_user_data_dir()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, message])


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# like the real window, which follows the project setting (nearest), a SubViewport defaults to linear
	_viewport.canvas_item_default_texture_filter = get_viewport().canvas_item_default_texture_filter
	add_child(_viewport)
	_editor = EDITOR_SCENE.instantiate()
	_viewport.add_child(_editor)
	await _frames(5)

	for test_case: Dictionary in CASES:
		var finished: Variant = await _run_case(test_case)
		check(finished == true, "case ran to the end (no script error)")

	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _run_case(test_case: Dictionary) -> bool:
	var config: MapTilesetConfiguration = load(test_case.config)
	_current = config.tileset_name
	var tag: String = config.tileset_name.to_snake_case()
	var store: PathStore = GlobalEditorData.path_store
	var paths_layer: PathsLayer = _editor.get_node("PathsLayer")
	var data_manager: MapDataManager = _editor.get_node("MapDataManager")

	data_manager._on_new_map_pressed()
	await _frames(2)
	_editor.current_map_tileset_configuration = config
	_editor.load_tileset_for_map(config)
	await _physics_frames(3) # layers get the tileset on physics frames (GlobalEditorData)
	await _frames(2)
	check(paths_layer.is_ready(), "paths layer has a geometry")
	var geometry: HexGeometry = paths_layer.geometry

	# ground: a blob of radius 4 around (0, 0), with a tall tile in front (below on screen) of a road cell
	# 2 steps west of the center, so its peak should cover the road there (the crossing stays visible)
	var world: TileMapLayer = _find_layer("World")
	var blob: Array = _blob(geometry, Vector2i.ZERO, 4)
	for cell: Vector2i in blob:
		world.set_cell(cell, 0, test_case.ground)
	var west_of_center: Vector2i = _neighbor_towards(geometry, _neighbor_towards(geometry, Vector2i.ZERO, Vector2.LEFT), Vector2.LEFT)
	var front: Vector2i = _neighbor_towards(geometry, west_of_center, Vector2.DOWN)
	world.set_cell(front, 0, test_case.tall)
	SignalBus.map_cells_changed.emit()

	var camera: Camera2D = _editor.camera
	camera.zoom = Vector2.ONE * test_case.zoom
	camera.global_position = paths_layer.to_global(geometry.cell_center(Vector2i.ZERO)) + Vector2(80, 40) / test_case.zoom
	await _frames(3)

	# --- road: drag from the far left cell, through the center, to the far right cell
	var west: Vector2i = _farthest(geometry, blob, Vector2.LEFT)
	var east: Vector2i = _farthest(geometry, blob, Vector2.RIGHT)
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.ROAD)
	await _drag([geometry.cell_center(west), geometry.cell_center(Vector2i.ZERO), geometry.cell_center(east)], paths_layer)
	var roads: Array[PathData] = _paths_of(store, PathData.Kind.ROAD)
	check(roads.size() == 1, "one road drawn (got %d)" % roads.size())
	if roads.is_empty():
		return false
	var road: PathData = roads[0]
	check(road.points[0] == west and road.points[road.points.size() - 1] == east, "road goes from the west cell to the east cell")
	check(road.points.has(Vector2i.ZERO), "road passes through the center")
	check(_is_chain(geometry, road), "every road step is between neighbors")

	# --- river: drag top to bottom just right of the center, crossing the road
	var inner_blob: Array = _blob(geometry, Vector2i.ZERO, 3) # keeps the ends away from the top bar
	var top: Vector2i = _farthest(geometry, inner_blob, Vector2.UP)
	var bottom: Vector2i = _farthest(geometry, inner_blob, Vector2.DOWN)
	var nudge: Vector2 = Vector2(geometry.unit_size() * 0.45, 0)
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.RIVER)
	await _drag([geometry.cell_center(top) + nudge, geometry.cell_center(Vector2i.ZERO) + nudge, geometry.cell_center(bottom) + nudge], paths_layer)
	var rivers: Array[PathData] = _paths_of(store, PathData.Kind.RIVER)
	check(rivers.size() == 1, "one river drawn (got %d)" % rivers.size())
	if rivers.is_empty():
		return false
	var river: PathData = rivers[0]
	check(river.anchor == PathData.Anchor.VERTEX and river.points.size() >= 4, "river runs along corners (%d points)" % river.points.size())
	check(_is_chain(geometry, river), "every river step is a hex edge")

	await _frames(3)
	var bridges: Array = paths_layer._bridges._bridges
	check(bridges.size() >= 1, "a bridge where the road crosses the river (got %d)" % bridges.size())
	check(paths_layer.z_index == world.z_index, "paths sit at the z of the World layer")
	var overhang_mirrors: int = paths_layer.get_node("Overhang").get_child_count()
	check(overhang_mirrors >= 1, "the tall tile in front of the road is mirrored above the paths")
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)
	SignalBus.path_dismissed.emit()
	await _frames(3)
	await _screenshot(tag + "_1_drawn")

	# --- undo / redo of both strokes
	var road_snapshot: PathData = road.duplicate_data()
	var river_snapshot: PathData = river.duplicate_data()
	_editor.undo_redo.undo()
	_editor.undo_redo.undo()
	check(store.get_all_paths().is_empty(), "undo twice removes both paths")
	_editor.undo_redo.redo()
	_editor.undo_redo.redo()
	check(store.get_all_paths().size() == 2, "redo twice brings them back")
	check(store.get_path_data(road.id) != null and store.get_path_data(road.id).same_as(road_snapshot), "redo restores the same road")

	# --- save, new map, load
	var save_path: String = _out_dir.path_join("e2e_%s.json" % tag)
	check(data_manager.save_current_map(save_path, config), "map saved")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(int(saved.get("format_version", 0)) == MapMigrations.CURRENT_FORMAT_VERSION and saved.paths.size() == 2, "save has format 2 and 2 paths")
	var centerline_before: PackedVector2Array = paths_layer.get_centerline(river.id)
	data_manager._on_new_map_pressed()
	await _frames(2)
	check(store.get_all_paths().is_empty(), "new map has no paths")
	data_manager.load_map_into_editor(save_path)
	await _physics_frames(3)
	await _frames(3)
	check(store.get_all_paths().size() == 2, "loaded map has 2 paths")
	check(store.get_path_data(river.id) != null and store.get_path_data(river.id).same_as(river_snapshot), "river identical after reload")
	check(paths_layer.get_centerline(river.id) == centerline_before, "river drawn exactly the same after reload (same seed)")
	await _screenshot(tag + "_2_reloaded")

	# --- erase the middle of the road with the erase tool, then undo
	var loaded_road: PathData = store.get_path_data(road.id)
	var middle: int = loaded_road.points.size() / 2
	var mid_point: Vector2 = (geometry.cell_center(loaded_road.points[middle - 1]) + geometry.cell_center(loaded_road.points[middle])) / 2.0
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.PATH_ERASE)
	await _drag([mid_point], paths_layer)
	check(_paths_of(store, PathData.Kind.ROAD).size() == 2, "erasing a middle segment splits the road in 2")
	_editor.undo_redo.undo()
	check(_paths_of(store, PathData.Kind.ROAD).size() == 1 and store.get_path_data(road.id).same_as(road_snapshot), "undo joins it back")
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)

	# --- select tool opens the panel with the road, changing the style there redraws it
	var panel: PathPanel = _editor.get_node("CanvasLayer/PathPanel")
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.PATH_SELECT)
	await _drag([mid_point], paths_layer)
	check(panel.details.visible and panel._current_path_id == road.id, "select tool opens the panel on the road")
	check(panel.path_name.text == road_snapshot.path_name, "panel shows the road name")
	var trail_index: int = -1
	for i: int in panel.style_option.item_count:
		if panel.style_option.get_item_metadata(i) == "builtin:trail":
			trail_index = i
	check(trail_index != -1, "road styles are listed")
	var line_before: PackedVector2Array = paths_layer.get_centerline(road.id)
	panel.style_option.select(trail_index)
	panel.style_option.item_selected.emit(trail_index)
	check(store.get_path_data(road.id).style_id == "builtin:trail", "style picked on the panel is stored")
	if paths_layer.effective_mode(store.get_path_data(road.id)) == "vector": # tile roads dont depend on the style
		check(paths_layer.get_centerline(road.id) != line_before, "road redrawn with the new style")
	panel.path_name.text_changed.emit("King's Road")
	check(store.get_path_data(road.id).path_name == "King's Road", "name typed on the panel is stored")
	SignalBus.path_dismissed.emit()
	check(not panel.details.visible, "dismiss hides the details")
	await _frames(2) # the panel shrinks back on the next frame
	check(panel.get_global_rect().end.y >= _viewport.size.y - PathPanel.BOTTOM_MARGIN - 1.0, "panel stays glued to the bottom after closing the details")

	# --- river through the hex centers (needed later for mod river tiles)
	panel.river_centers_check.button_pressed = true
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.RIVER)
	var south_west: Vector2i = _farthest(geometry, inner_blob, Vector2(-1, 1).normalized())

	await _drag([geometry.cell_center(south_west), geometry.cell_center(west_of_center)], paths_layer)
	var center_rivers: Array[PathData] = []
	for path: PathData in _paths_of(store, PathData.Kind.RIVER):
		if path.anchor == PathData.Anchor.CELL:
			center_rivers.append(path)
	check(center_rivers.size() == 1 and _is_chain(geometry, center_rivers[0]), "river by centers is a chain of cells (%d rivers: %s, from %s to %s, mouse on tools: %s)" % [
		center_rivers.size(), center_rivers.map(func(p: PathData) -> Array: return p.points), south_west, west_of_center, _editor.is_mouse_on_tools()])
	panel.river_centers_check.button_pressed = false
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)

	# --- phase 2: the mod's own road/river tiles
	await _frames(2)
	var road_tiles: TileMapLayer = paths_layer.get_node("RoadTiles")
	var river_tiles: TileMapLayer = paths_layer.get_node("RiverTiles")
	var center_river: PathData = center_rivers[0] if not center_rivers.is_empty() else null
	if config.provides_road_tiles():
		check(paths_layer.effective_mode(store.get_path_data(road.id)) == "tile", "road uses the tileset's road tiles")
		var road_cells: int = store.get_path_data(road.id).points.size()
		var road_missing: int = paths_layer.missing_tiles_of(store.get_path_data(road.id)).size()
		check(road_tiles.get_used_cells().size() + road_missing == road_cells, "every road hex is a tile or a vector stub")
		check(road_tiles.get_used_cells().size() > road_missing, "most of the road uses tiles (%d tiles, %d vector)" % [road_tiles.get_used_cells().size(), road_missing])
	else:
		check(paths_layer.effective_mode(store.get_path_data(road.id)) == "vector", "no road tiles in this tileset, road falls back to vector")
		check(road_tiles.get_used_cells().is_empty(), "road tile layer stays empty")
	if config.provides_river_tiles():
		check(paths_layer.effective_mode(center_river) == "tile", "river by centers uses the tileset's river tiles")
		check(river_tiles.get_used_cells().size() + paths_layer.missing_tiles_of(center_river).size() == center_river.points.size(), "every river hex is a tile or a vector stub")
	else:
		check(river_tiles.get_used_cells().is_empty(), "no river tiles in this tileset, river layer stays empty")
	check(paths_layer.effective_mode(store.get_path_data(river.id)) == "vector", "rivers along the edges are always vector")

	var tiled: PathData = store.get_path_data(road.id) if config.provides_road_tiles() else center_river
	var tile_layer: TileMapLayer = road_tiles if tiled.kind == PathData.Kind.ROAD else river_tiles
	if (config.provides_road_tiles() if tiled.kind == PathData.Kind.ROAD else config.provides_river_tiles()):
		var tiles_before: int = tile_layer.get_used_cells().size()
		await _frames(2)
		await _screenshot(tag + "_4_tiles")

		# forcing vector on the path, then undo
		SignalBus.path_selected.emit(tiled.id)
		panel.path_mode_option.select(1)
		panel.path_mode_option.item_selected.emit(1)
		await _frames(2)
		check(tile_layer.get_used_cells().is_empty(), "path forced to vector leaves the tile layer")
		_editor.undo_redo.undo()
		await _frames(2)
		check(tile_layer.get_used_cells().size() == tiles_before, "undo brings the tiles back")

		# picking a tile by hand for a hex that had none, it is saved with the map
		SignalBus.path_selected.emit(tiled.id)
		await _frames(2)
		var missing_before: Dictionary = paths_layer.missing_tiles_of(store.get_path_data(tiled.id))
		check(not missing_before.is_empty() and panel.missing_row.visible, "panel lists the hexes without a tile")
		if not missing_before.is_empty():
			var picked_cell: Vector2i = panel._selected_cell
			(panel.tile_choices.get_child(0) as TextureButton).pressed.emit()
			await _frames(2)
			check(tile_layer.get_cell_source_id(picked_cell) != -1, "hex %s now has the tile picked by hand" % picked_cell)
			check(store.get_path_data(tiled.id).tile_exceptions.has(str(picked_cell)), "pick saved as an exception")
			data_manager.save_current_map(save_path, config)
			data_manager.load_map_into_editor(save_path)
			await _physics_frames(3)
			await _frames(3)
			check(tile_layer.get_cell_source_id(picked_cell) != -1, "picked tile still there after reload")
			_editor.undo_redo.clear_history()

		# map wide vector mode, then back to auto
		store.render_mode = "vector"
		await _frames(2)
		check(tile_layer.get_used_cells().is_empty(), "map mode Vector draws every path as vector")
		store.render_mode = "auto"
		await _frames(2)
		check(not tile_layer.get_used_cells().is_empty(), "map mode Auto goes back to tiles")
		SignalBus.path_dismissed.emit()

	# --- picking a tile pencil drops the road tool and vice versa
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.ROAD)
	_editor.tiles_grid_container.get_child(0).pressed.emit()
	check(GlobalEditorData.active_tool == GlobalEditorData.EditorTool.PAINT, "picking a tile switches to painting")
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.RIVER)
	check(not _editor.is_pencil_selected(), "picking the river tool drops the pencil")
	GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)

	# --- phase 3: biome smoothing and coastlines (only looks, never data)
	var blend: GroundBlend = _editor.get_node("GroundBlend")
	world = _find_layer("World") # the map was reloaded above, the old layer is gone
	# the blend saves these as user preferences, put them back at the end
	var blend_was: Array = [blend.enabled, blend.intensity, blend.coastlines]
	var east_side: Array = _blob(geometry, _farthest(geometry, blob, Vector2.RIGHT), 1)
	var north_west: Vector2i = _farthest(geometry, blob, Vector2(-1, -1).normalized())
	for cell: Vector2i in east_side:
		if blob.has(cell):
			world.set_cell(cell, 0, test_case.water)
	for cell: Vector2i in _blob(geometry, north_west, 1):
		if blob.has(cell):
			world.set_cell(cell, 0, test_case.other) # another biome, to see the borders blend
	SignalBus.map_cells_changed.emit()
	blend.coastlines = true
	camera.zoom = Vector2.ONE * test_case.zoom
	camera.global_position = paths_layer.to_global(geometry.cell_center(Vector2i.ZERO)) + Vector2(80, 40) / test_case.zoom
	blend.enabled = false
	await _frames(4)
	check(blend.get_node("Coastlines").edge_count() > 0, "coastline drawn where water meets land")
	var off_image: Image = await _capture()
	var off_json: String = await _save_text(data_manager, config, _out_dir.path_join("blend_off_%s.json" % tag))
	await _screenshot(tag + "_5_blend_off")

	blend.enabled = true
	blend.intensity = 0.0
	await _frames(4)
	var zero_image: Image = await _capture()
	var zero_diff: int = 0
	for y: int in range(140, 640, 2):
		for x: int in range(300, 1550, 2):
			if not _same_color(off_image.get_pixel(x, y), zero_image.get_pixel(x, y)):
				zero_diff += 1
	# soft edged art spilling out of its hex gets alpha blended over a slightly different background, < 1% is fine
	check(zero_diff < 1500, "smoothing at intensity 0 looks like off (%d of ~156k sampled pixels differ)" % zero_diff)
	blend.intensity = 1.0
	await _frames(4)
	check(not world.visible, "ground layer is hidden while the smoothing draws it")
	var on_image: Image = await _capture()
	var mask_image: Image = blend._mask_viewport.get_texture().get_image()
	var mask_canvas: Transform2D = _viewport.get_canvas_transform()
	var probe_cell: Vector2i = _neighbor_towards(geometry, Vector2i.ZERO, Vector2.UP)
	var probe_edge: Array = geometry.shared_edge(probe_cell, Vector2i.ZERO)
	var probe_mid: Vector2 = (geometry.vertex_position(probe_edge[0]) + geometry.vertex_position(probe_edge[1])) / 2.0
	var at_center: float = mask_image.get_pixelv(Vector2i(mask_canvas * paths_layer.to_global(geometry.cell_center(probe_cell)))).r
	var at_edge: float = mask_image.get_pixelv(Vector2i(mask_canvas * paths_layer.to_global(probe_mid))).r
	check(at_center > 0.85 and at_edge < 0.15, "edge mask lines up with the hexes on screen (center %.2f, edge %.2f)" % [at_center, at_edge])
	var on_json: String = await _save_text(data_manager, config, _out_dir.path_join("blend_on_%s.json" % tag))
	await _screenshot(tag + "_6_blend_on")
	check(on_json == off_json, "turning the smoothing on doesnt change the saved map")

	# hex centers untouched, borders changed
	var canvas: Transform2D = _viewport.get_canvas_transform()
	var compared: int = 0
	var center_differences: int = 0
	for cell: Vector2i in blob:
		var screen: Vector2i = Vector2i(canvas * paths_layer.to_global(geometry.cell_center(cell)))
		if not Rect2i(Vector2i(300, 140), Vector2i(1250, 500)).has_point(screen): # skip cells under the UI panels
			continue
		if _near_paths(store, geometry, cell) or cell == front or _neighbor_towards(geometry, cell, Vector2.DOWN) == front:
			continue
		compared += 1
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, -1)]:
			if not _same_color(off_image.get_pixelv(screen + offset), on_image.get_pixelv(screen + offset)):
				center_differences += 1
	check(compared >= 5, "compared enough hex centers (%d)" % compared)
	check(center_differences == 0, "hex centers are pixel identical with the smoothing on (%d differences in %d hexes)" % [center_differences, compared])
	var changed: int = 0
	for y: int in range(140, 640, 3):
		for x: int in range(300, 1550, 3):
			if not _same_color(off_image.get_pixel(x, y), on_image.get_pixel(x, y)):
				changed += 1
	check(changed > 200, "borders between hexes changed with the smoothing on (%d sampled pixels)" % changed)

	blend.enabled = false
	await _frames(3)
	check(world.visible, "turning it off shows the original layer again")
	var back_image: Image = await _capture()
	check(back_image.get_data() == off_image.get_data(), "turning it off gives back exactly the original picture")
	blend.enabled = blend_was[0]
	blend.intensity = blend_was[1]
	blend.coastlines = blend_was[2]

	# close-up of the crossing and of the tall tile in front of the road
	camera.zoom = Vector2.ONE * test_case.zoom * 2.0
	camera.global_position = paths_layer.to_global(geometry.cell_center(west_of_center)) + Vector2(-60, 20) / camera.zoom.x
	await _frames(3)
	await _screenshot(tag + "_3_closeup")
	return true


# --- helpers ---

func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _save_text(data_manager: MapDataManager, config: MapTilesetConfiguration, path: String) -> String:
	data_manager.save_current_map(path, config)
	await _frames(1)
	return FileAccess.get_file_as_string(path)


static func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


## True when a road/river goes through or along the cell (they are drawn the same with or without smoothing,
## but bridges and tile stubs make the comparison noisy)
func _near_paths(store: PathStore, geometry: HexGeometry, cell: Vector2i) -> bool:
	for path: PathData in store.get_all_paths():
		for point: Variant in path.points:
			if point is Vector2i and (point == cell or geometry.are_adjacent(point, cell)):
				return true
			if point is Array and (point as Array).has(cell):
				return true
	return false

func _drag(local_points: Array, paths_layer: PathsLayer) -> void:
	var canvas: Transform2D = _viewport.get_canvas_transform()
	var screen: Array[Vector2] = []
	for local: Vector2 in local_points:
		screen.append(canvas * paths_layer.to_global(local))

	_push_mouse(screen[0], true, true)
	await _frames(1)
	for i: int in screen.size() - 1:
		var steps: int = maxi(int(screen[i].distance_to(screen[i + 1]) / 6.0), 1)
		for step: int in range(1, steps + 1):
			_push_motion(screen[i].lerp(screen[i + 1], float(step) / steps))
	await _frames(1)
	_push_mouse(screen[screen.size() - 1], false, false)
	await _frames(2)


func _push_mouse(position: Vector2, pressed: bool, _first: bool) -> void:
	_push_motion(position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_viewport.push_input(event, true)


func _push_motion(position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_viewport.push_input(event, true)


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


func _screenshot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _out_dir.path_join(file_name + ".png")
	_viewport.get_texture().get_image().save_png(path)
	print("  screenshot: ", path)


func _find_layer(layer_name: String) -> TileMapLayer:
	for layer: UserLayer in GlobalEditorData.user_layers.get_all_layers():
		if layer.layer_name == layer_name:
			return layer.layer_tilemap_ref
	return null


func _paths_of(store: PathStore, kind: PathData.Kind) -> Array[PathData]:
	var result: Array[PathData] = []
	for path: PathData in store.get_all_paths():
		if path.kind == kind:
			result.append(path)
	return result


func _is_chain(geometry: HexGeometry, path: PathData) -> bool:
	for i: int in path.points.size() - 1:
		var a: Variant = path.points[i]
		var b: Variant = path.points[i + 1]
		var adjacent: bool = geometry.are_adjacent(a, b) if path.anchor == PathData.Anchor.CELL else geometry.are_vertices_adjacent(a, b)
		if not adjacent:
			return false
	return true


func _blob(geometry: HexGeometry, center: Vector2i, radius: int) -> Array:
	var seen: Dictionary = {center: true}
	var frontier: Array = [center]
	for _ring: int in radius:
		var next: Array = []
		for cell: Vector2i in frontier:
			for other: Vector2i in geometry.neighbors(cell):
				if not seen.has(other):
					seen[other] = true
					next.append(other)
		frontier = next
	return seen.keys()


func _farthest(geometry: HexGeometry, cells: Array, direction: Vector2) -> Vector2i:
	var best: Vector2i = cells[0]
	var center: Vector2 = geometry.cell_center(Vector2i.ZERO)
	for cell: Vector2i in cells:
		var offset: Vector2 = geometry.cell_center(cell) - center
		var best_offset: Vector2 = geometry.cell_center(best) - center
		# far along the direction, but close to the axis through the center
		if offset.dot(direction) - absf(offset.cross(direction)) * 1.5 > best_offset.dot(direction) - absf(best_offset.cross(direction)) * 1.5:
			best = cell
	return best


func _neighbor_towards(geometry: HexGeometry, cell: Vector2i, direction: Vector2) -> Vector2i:
	var best: Vector2i = cell
	var best_dot: float = -INF
	for other: Vector2i in geometry.neighbors(cell):
		var dot: float = (geometry.cell_center(other) - geometry.cell_center(cell)).normalized().dot(direction)
		if dot > best_dot:
			best_dot = dot
			best = other
	return best
