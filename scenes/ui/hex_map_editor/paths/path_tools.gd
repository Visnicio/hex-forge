## Mouse tools to draw, erase and select roads/rivers, plus the hover feedback on the map.[br]
## - road / river: click and drag from cell to cell (or corner to corner); starting on the end of an existing
##   path of the same kind extends it, going back over the previous point undoes the last step[br]
## - erase: click/drag over a segment removes it (splitting the path), shift+click removes the whole path.
##   Right click with the road/river tools also erases[br]
## - select: click a path to edit its name, description and style on the [PathPanel][br]
## Every stroke is one action on the editor [UndoRedo], with snapshots of the paths it touched
class_name PathTools extends Node2D

@export var editor: HexMapEditor
@export var path_store: PathStore
@export var paths_layer: PathsLayer

## Anchor used by the river tool: rivers along the hex edges (default) or through the centers (mod river tiles)
var river_anchor: PathData.Anchor = PathData.Anchor.VERTEX

const HOVER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.7)
const SELECTED_COLOR: Color = Color(1.0, 0.85, 0.3, 0.85)
const ERASE_COLOR: Color = Color(1.0, 0.25, 0.2, 0.9)
## How close (relative to the hex size) the mouse needs to be to pick a path
const PICK_DISTANCE: float = 0.3

var selected_path_id: String = ""

enum StrokeKind { NONE, DRAW, ERASE }
var _stroke: StrokeKind = StrokeKind.NONE
var _stroke_path_id: String = ""
## True when extending a path from its first point instead of its last one
var _stroke_prepend: bool = false
## Undo snapshots of the paths touched by the current stroke: {path_id: PathData or null}
var _before: Dictionary = {}
var _new_path_ids: Array[String] = []


func _ready() -> void:
	z_index = 20 # above layers and paths, below the pencil hover/markers UI doesnt matter here
	SignalBus.tool_changed.connect(_on_tool_changed)
	SignalBus.path_selected.connect(func(path_id: String) -> void: selected_path_id = path_id)
	SignalBus.path_dismissed.connect(func() -> void: selected_path_id = "")
	path_store.store_reset.connect(func() -> void:
		_stroke = StrokeKind.NONE
		selected_path_id = "")


func _process(_delta: float) -> void:
	global_transform = paths_layer.global_transform
	queue_redraw()


func _on_tool_changed(new_tool: int) -> void:
	if _stroke != StrokeKind.NONE:
		_commit_stroke()
	if GlobalEditorData.is_path_tool_active():
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif new_tool == GlobalEditorData.EditorTool.NONE:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if not GlobalEditorData.is_path_tool_active() or not paths_layer.is_ready():
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)
		return

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		if event.pressed and _stroke == StrokeKind.NONE:
			if editor.is_mouse_on_tools():
				return
			_begin_stroke(event)
			get_viewport().set_input_as_handled()
		elif not event.pressed and _stroke != StrokeKind.NONE:
			_commit_stroke()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _stroke != StrokeKind.NONE:
		_continue_stroke()


func _mouse_local() -> Vector2:
	return paths_layer.to_local(paths_layer.get_global_mouse_position())


func _tool_kind() -> PathData.Kind:
	return PathData.Kind.RIVER if GlobalEditorData.active_tool == GlobalEditorData.EditorTool.RIVER else PathData.Kind.ROAD


func _tool_anchor() -> PathData.Anchor:
	return river_anchor if _tool_kind() == PathData.Kind.RIVER else PathData.Anchor.CELL


func _point_under_mouse(anchor: PathData.Anchor) -> Variant:
	if anchor == PathData.Anchor.CELL:
		return paths_layer.geometry.cell_at(_mouse_local())
	return paths_layer.geometry.nearest_vertex(_mouse_local())


# --- strokes ---

func _begin_stroke(event: InputEventMouseButton) -> void:
	get_viewport().gui_release_focus() # so ctrl+z goes to the map and not to a text field left focused
	_before.clear()
	_new_path_ids.clear()
	var active_tool: int = GlobalEditorData.active_tool

	if active_tool == GlobalEditorData.EditorTool.PATH_SELECT:
		var picked: Dictionary = pick_segment(_mouse_local())
		if picked.is_empty():
			SignalBus.path_dismissed.emit()
		else:
			SignalBus.path_selected.emit(picked.path_id)
		return

	var erasing: bool = active_tool == GlobalEditorData.EditorTool.PATH_ERASE or event.button_index == MOUSE_BUTTON_RIGHT
	if erasing:
		_stroke = StrokeKind.ERASE
		if event.shift_pressed:
			var picked: Dictionary = pick_segment(_mouse_local())
			if not picked.is_empty():
				_snapshot(picked.path_id)
				path_store.remove_path(picked.path_id)
		else:
			_erase_under_mouse()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_stroke = StrokeKind.DRAW
	var anchor: PathData.Anchor = _tool_anchor()
	var point: Variant = _point_under_mouse(anchor)
	if point is Array and (point as Array).is_empty():
		_stroke = StrokeKind.NONE
		return

	# starting on the end of a path of the same kind continues it
	var target: PathData = _find_path_ending_at(point, _tool_kind(), anchor)
	if target != null:
		_snapshot(target.id)
		_stroke_path_id = target.id
		_stroke_prepend = target.points[0] == point and target.points[target.points.size() - 1] != point
	else:
		var new_path: PathData = PathData.create(_tool_kind(), anchor)
		new_path.points = [point]
		_before[new_path.id] = null
		_new_path_ids.append(new_path.id)
		_stroke_path_id = new_path.id
		_stroke_prepend = false
		path_store.set_path(new_path)


func _continue_stroke() -> void:
	if _stroke == StrokeKind.ERASE:
		if not Input.is_key_pressed(KEY_SHIFT):
			_erase_under_mouse()
		return

	var path: PathData = path_store.get_path_data(_stroke_path_id)
	if path == null:
		return
	var point: Variant = _point_under_mouse(path.anchor)
	if point is Array and (point as Array).is_empty():
		return
	var last: Variant = _end_point(path, 0)
	if point == last:
		return

	var geometry: HexGeometry = paths_layer.geometry
	# going back over the previous point undoes the last step
	if path.points.size() >= 2 and point == _end_point(path, 1):
		_pop_end(path)
	elif _adjacent(path.anchor, last, point):
		_push_end(path, point)
	else:
		var route: Array = geometry.cell_route(last, point) if path.anchor == PathData.Anchor.CELL else geometry.vertex_route(last, point)
		for step: Variant in route:
			_push_end(path, step)
	path_store.notify_changed(path.id)


func _commit_stroke() -> void:
	var stroke: StrokeKind = _stroke
	_stroke = StrokeKind.NONE
	if stroke == StrokeKind.NONE:
		return

	var after: Dictionary = {}
	var changed: bool = false
	for path_id: String in _before.keys():
		var current: PathData = path_store.get_path_data(path_id)
		if current != null and current.points.size() < 2:
			# a click that never left its cell, or an erase that left a single point behind
			path_store.remove_path(path_id)
			current = null
		after[path_id] = current.duplicate_data() if current != null else null
		var before: PathData = _before[path_id]
		if (before == null) != (current == null) or (before != null and not before.same_as(current)):
			changed = true

	if changed:
		var undo_redo: UndoRedo = editor.undo_redo
		undo_redo.create_action("Erase Path" if stroke == StrokeKind.ERASE else ("Draw River" if _tool_kind() == PathData.Kind.RIVER else "Draw Road"))
		undo_redo.add_do_method(path_store.apply_snapshots.bind(after))
		undo_redo.add_undo_method(path_store.apply_snapshots.bind(_before.duplicate()))
		undo_redo.commit_action(false)

	if stroke == StrokeKind.DRAW and path_store.has_path(_stroke_path_id):
		SignalBus.path_selected.emit(_stroke_path_id)
	elif stroke == StrokeKind.ERASE and not path_store.has_path(selected_path_id):
		SignalBus.path_dismissed.emit()
	_before.clear()


## Undoable change made by the panel (style, render mode, tile picked by hand...):
## [param mutate] receives the live [PathData] and edits it
func commit_edit(path_id: String, action_name: String, mutate: Callable) -> void:
	var path: PathData = path_store.get_path_data(path_id)
	if path == null:
		return
	var before: PathData = path.duplicate_data()
	mutate.call(path)
	if path.same_as(before):
		return
	editor.undo_redo.create_action(action_name)
	editor.undo_redo.add_do_method(path_store.apply_snapshots.bind({path_id: path.duplicate_data()}))
	editor.undo_redo.add_undo_method(path_store.apply_snapshots.bind({path_id: before}))
	editor.undo_redo.commit_action() # applies the "do" snapshot, which also redraws the path


## Undoable removal of a whole path (used by the panel delete button)
func delete_path(path_id: String) -> void:
	var path: PathData = path_store.get_path_data(path_id)
	if path == null:
		return
	editor.undo_redo.create_action("Delete Path")
	editor.undo_redo.add_do_method(path_store.apply_snapshots.bind({path_id: null}))
	editor.undo_redo.add_undo_method(path_store.apply_snapshots.bind({path_id: path.duplicate_data()}))
	editor.undo_redo.commit_action()
	SignalBus.path_dismissed.emit()


func _snapshot(path_id: String) -> void:
	if not _before.has(path_id):
		var path: PathData = path_store.get_path_data(path_id)
		_before[path_id] = path.duplicate_data() if path != null else null


## Point at the end being drawn, [param back] steps before it
func _end_point(path: PathData, back: int) -> Variant:
	return path.points[back] if _stroke_prepend else path.points[path.points.size() - 1 - back]


func _push_end(path: PathData, point: Variant) -> void:
	if _stroke_prepend:
		path.points.push_front(point)
	else:
		path.points.push_back(point)


func _pop_end(path: PathData) -> void:
	if _stroke_prepend:
		path.points.pop_front()
	else:
		path.points.pop_back()


func _adjacent(anchor: PathData.Anchor, a: Variant, b: Variant) -> bool:
	if anchor == PathData.Anchor.CELL:
		return paths_layer.geometry.are_adjacent(a, b)
	return paths_layer.geometry.are_vertices_adjacent(a, b)


func _find_path_ending_at(point: Variant, kind: PathData.Kind, anchor: PathData.Anchor) -> PathData:
	var found: PathData = null
	for path: PathData in path_store.get_all_paths():
		if path.kind != kind or path.anchor != anchor or path.points.is_empty():
			continue
		if path.points[path.points.size() - 1] == point or path.points[0] == point:
			if path.id == selected_path_id:
				return path # the selected one wins when 2 paths end on the same point
			found = path
	return found


func _erase_under_mouse() -> void:
	var picked: Dictionary = pick_segment(_mouse_local())
	if picked.is_empty():
		return
	var path: PathData = path_store.get_path_data(picked.path_id)
	_snapshot(path.id)
	var index: int = picked.segment

	var tail: Array = path.points.slice(index + 1)
	path.points = path.points.slice(0, index + 1)
	if tail.size() >= 2:
		var second: PathData = path.duplicate_data()
		second.id = PathData.new_id()
		second.points = tail
		second.tile_exceptions = {}
		_before[second.id] = null
		path_store.set_path(second)
	if path.points.size() < 2:
		path_store.remove_path(path.id)
	else:
		path_store.notify_changed(path.id)


## Closest path segment to the point: {path_id, segment} or empty when nothing is near
func pick_segment(local_position: Vector2) -> Dictionary:
	var geometry: HexGeometry = paths_layer.geometry
	var best: Dictionary = {}
	var best_distance: float = pow(geometry.unit_size() * PICK_DISTANCE, 2.0)
	for path: PathData in path_store.get_all_paths():
		for i: int in path.points.size() - 1:
			var a: Vector2 = VectorPathRenderer.point_position(path, i, geometry)
			var b: Vector2 = VectorPathRenderer.point_position(path, i + 1, geometry)
			var distance: float = Geometry2D.get_closest_point_to_segment(local_position, a, b).distance_squared_to(local_position)
			if distance < best_distance:
				best_distance = distance
				best = {"path_id": path.id, "segment": i}
	return best


# --- feedback ---

func _draw() -> void:
	if not paths_layer.is_ready():
		return
	var geometry: HexGeometry = paths_layer.geometry
	var unit: float = geometry.unit_size()

	if selected_path_id != "" and path_store.has_path(selected_path_id):
		var line: PackedVector2Array = paths_layer.get_centerline(selected_path_id)
		if line.size() >= 2:
			draw_polyline(line, SELECTED_COLOR, unit * 0.025, true)

	if not GlobalEditorData.is_path_tool_active() or editor.is_mouse_on_tools():
		return

	var mouse: Vector2 = _mouse_local()
	match GlobalEditorData.active_tool:
		GlobalEditorData.EditorTool.ROAD, GlobalEditorData.EditorTool.RIVER:
			if _tool_anchor() == PathData.Anchor.CELL:
				var outline: PackedVector2Array = geometry.corners(geometry.cell_at(mouse))
				outline.append(outline[0])
				draw_polyline(outline, HOVER_COLOR, unit * 0.015, true)
			else:
				var vertex: Array = geometry.nearest_vertex(mouse)
				if not vertex.is_empty():
					draw_circle(geometry.vertex_position(vertex), unit * 0.05, HOVER_COLOR, true, -1.0, true)
		GlobalEditorData.EditorTool.PATH_ERASE, GlobalEditorData.EditorTool.PATH_SELECT:
			var picked: Dictionary = pick_segment(mouse)
			if picked.is_empty():
				return
			var path: PathData = path_store.get_path_data(picked.path_id)
			var color: Color = ERASE_COLOR if GlobalEditorData.active_tool == GlobalEditorData.EditorTool.PATH_ERASE else HOVER_COLOR
			if Input.is_key_pressed(KEY_SHIFT) or GlobalEditorData.active_tool == GlobalEditorData.EditorTool.PATH_SELECT:
				var whole: PackedVector2Array = paths_layer.get_centerline(path.id)
				if whole.size() >= 2:
					draw_polyline(whole, color, unit * 0.03, true)
			else:
				draw_line(VectorPathRenderer.point_position(path, picked.segment, geometry),
					VectorPathRenderer.point_position(path, picked.segment + 1, geometry), color, unit * 0.03, true)
