## Runtime owner of the roads/rivers of the map open in the editor (same idea as [HexDataStore]).[br]
## Paths have no node of their own, renderers build their visuals from here and react to the signals,
## and [MapDataManager] snapshots it into [MapData] on save
class_name PathStore extends Node

## A path was created, edited (call [method notify_changed] after editing one) or removed
signal path_changed(path_id: String)
## Every path was replaced (new map / map loaded)
signal store_reset()
## Seed, anchor layer or render mode changed
signal settings_changed()

var path_seed: int = 0
## Name of the user layer the paths are drawn above, empty = bottom layer
var anchor_layer: String = "":
	set(value):
		anchor_layer = value
		settings_changed.emit()
## Map default of [member PathData.render_mode]
var render_mode: String = "auto":
	set(value):
		if value == render_mode:
			return
		render_mode = value
		settings_changed.emit()

var _paths: Dictionary[String, PathData] = {}


func _ready() -> void:
	GlobalEditorData.path_store = self
	path_seed = randi()


func _exit_tree() -> void:
	if GlobalEditorData.path_store == self:
		GlobalEditorData.path_store = null


func has_path(path_id: String) -> bool:
	return _paths.has(path_id)


## The live path (edit it and call [method notify_changed]), or [code]null[/code]
func get_path_data(path_id: String) -> PathData:
	return _paths.get(path_id, null)


func get_all_paths() -> Array[PathData]:
	var result: Array[PathData] = []
	result.assign(_paths.values())
	return result


func set_path(data: PathData) -> void:
	_paths[data.id] = data
	path_changed.emit(data.id)


func remove_path(path_id: String) -> void:
	if _paths.erase(path_id):
		path_changed.emit(path_id)


func notify_changed(path_id: String) -> void:
	path_changed.emit(path_id)


## Applies undo/redo snapshots: [code]{path_id: PathData or null}[/code], null removes the path.[br]
## Stores copies, so the snapshots kept by UndoRedo are never edited afterwards
func apply_snapshots(snapshots: Dictionary) -> void:
	for path_id: String in snapshots.keys():
		var snapshot: PathData = snapshots[path_id]
		if snapshot == null:
			remove_path(path_id)
		else:
			set_path(snapshot.duplicate_data())


## New empty map
func reset() -> void:
	_paths.clear()
	path_seed = randi()
	anchor_layer = ""
	render_mode = "auto"
	store_reset.emit()


func load_from(map_data: MapData) -> void:
	_paths.assign(map_data.paths)
	path_seed = map_data.path_seed
	anchor_layer = map_data.path_anchor_layer
	render_mode = map_data.path_render_mode
	store_reset.emit()


func write_to(map_data: MapData) -> void:
	map_data.paths = {}
	for data: PathData in _paths.values():
		if data.points.size() >= 2: # a lone point draws nothing, its a leftover of a cancelled stroke
			map_data.paths[data.id] = data
	map_data.path_seed = path_seed
	map_data.path_anchor_layer = anchor_layer
	map_data.path_render_mode = render_mode
