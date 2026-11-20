## Runtime owner of the per-hex data (name, free text...) of the map open in the editor.[br]
## Markers and layers live as nodes in the scene, so the scene is their source of truth and
## [code]MapDataManager[/code] reads them back on save. Hexes have no node, so this store is
## their source of truth while the editor is open, and gets snapshotted into [code]MapData[/code] on save.[br]
## Its a Node so its lifetime is tied to the editor scene, it has no children, it only holds [code]HexData[/code]s
class_name HexDataStore extends Node

## Emitted whenever a hex is created, edited through [method notify_changed] or removed
signal hex_changed(tile_coord: Vector2i)
## Emitted when the whole store is wiped or replaced (new map / map loaded)
signal store_reset()

var _hexes: Dictionary[Vector2i, HexData] = {}


func _ready() -> void:
	GlobalEditorData.hex_data_store = self # registers on globals so UI (e.g. HexDataPanel) can reach it


func _exit_tree() -> void:
	# avoids leaving a reference to a freed node on globals if the editor scene goes away
	if GlobalEditorData.hex_data_store == self:
		GlobalEditorData.hex_data_store = null


func has_hex(tile_coord: Vector2i) -> bool:
	return _hexes.has(tile_coord)


## Returns the data for the hex or [code]null[/code] if it has none
func get_hex(tile_coord: Vector2i) -> HexData:
	return _hexes.get(tile_coord, null)


## Returns the data for the hex, creating an empty one if it has none yet
func get_or_create_hex(tile_coord: Vector2i) -> HexData:
	if not _hexes.has(tile_coord):
		var new_hex: HexData = HexData.new()
		new_hex.tile_coord = tile_coord
		_hexes[tile_coord] = new_hex
		hex_changed.emit(tile_coord)
	return _hexes[tile_coord]


## HexData is a plain RefCounted, editing its fields does not emit anything,
## call this after editing one if something needs to react (e.g. drawing an icon on hexes with notes)
func notify_changed(tile_coord: Vector2i) -> void:
	hex_changed.emit(tile_coord)


func remove_hex(tile_coord: Vector2i) -> void:
	if _hexes.erase(tile_coord):
		hex_changed.emit(tile_coord)


func clear() -> void:
	_hexes.clear()
	store_reset.emit()


## Replaces everything in the store with the given hexes (used when loading a map)
func load_hexes(hexes: Dictionary[Vector2i, HexData]) -> void:
	_hexes.assign(hexes) # copies the entries, so MapData and the store dont share the same dictionary
	store_reset.emit()


## Returns the hexes worth saving, skipping the ones that were created but never filled
func get_hexes_to_save() -> Dictionary[Vector2i, HexData]:
	var result: Dictionary[Vector2i, HexData] = {}
	for tile_coord: Vector2i in _hexes.keys():
		if not _hexes[tile_coord].is_empty():
			result[tile_coord] = _hexes[tile_coord]
	return result
