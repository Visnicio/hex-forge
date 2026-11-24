extends Node

@warning_ignore("unused_signal")
signal marker_pressed(marker: WorldMarker)

@warning_ignore("unused_signal")
signal marker_data_panel_dismissed(marker: WorldMarker)

@warning_ignore("unused_signal")
signal layer_selected(new_layer_selected: UserLayer)

@warning_ignore("unused_signal")
signal layer_reorder_requested(layer: UserLayer, direction: int)

@warning_ignore("unused_signal")
signal hex_selected(position_in_tile_coords: Vector2i)

@warning_ignore("unused_signal")
signal hex_dismissed()

## Emitted whenever cells of the layers tilemaps are painted/erased (brush, undo/redo, map load)[br]
## TileMapLayer.changed does NOT fire on set_cell, only on property changes, so we need our own
@warning_ignore("unused_signal")
signal map_cells_changed()

## Emitted by [method GlobalEditorData.set_active_tool], the value is a [enum GlobalEditorData.EditorTool]
@warning_ignore("unused_signal")
signal tool_changed(new_tool: int)

## A road/river was selected (path tools, panel), [code]path_id[/code] is a key of the [PathStore]
@warning_ignore("unused_signal")
signal path_selected(path_id: String)

@warning_ignore("unused_signal")
signal path_dismissed()
