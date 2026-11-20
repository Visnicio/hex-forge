## Shows the size of the map in hexes (columns x rows), counting every painted cell of every layer
class_name MapSizeLabel extends Label

## Node that holds every layer TileMapLayer (same one UserLayers uses)
@export var tilemaps_holder: Node2D

var _refresh_queued: bool = false


func _ready() -> void:
	# painting, erasing, undo/redo and loading all go through this signal
	# (TileMapLayer.changed would be nicer, but it does NOT fire on set_cell)
	SignalBus.map_cells_changed.connect(_queue_refresh)
	# layers being added/deleted (new map, add layer, deleting a layer with tiles) also change the size
	tilemaps_holder.child_entered_tree.connect(func(_node: Node): _queue_refresh())
	tilemaps_holder.child_exiting_tree.connect(func(_node: Node): _queue_refresh())
	_queue_refresh()


## A brush stroke changes many cells in the same frame, this makes it recalculate only once per frame
func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	var map_rect: Rect2i = get_map_rect()
	text = "Map size: %d × %d hexes" % [map_rect.size.x, map_rect.size.y]


## Rect (in tile coords) that contains every painted cell of every layer, empty if nothing is painted
func get_map_rect() -> Rect2i:
	var result: Rect2i = Rect2i()
	var has_any_cell: bool = false

	for child in tilemaps_holder.get_children():
		# delete_all_layers uses queue_free, so the old tilemaps may still be here this frame
		if not child is TileMapLayer or child.is_queued_for_deletion():
			continue
		var layer_rect: Rect2i = child.get_used_rect()
		if layer_rect.size == Vector2i.ZERO:
			continue
		result = layer_rect if not has_any_cell else result.merge(layer_rect)
		has_any_cell = true

	return result
