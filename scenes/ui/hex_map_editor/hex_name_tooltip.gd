## Small tooltip that follows the mouse showing the name of the hex under it, only when that hex has a name.[br]
## It lives on its own CanvasLayer (not on the main one) because [method HexMapEditor.is_mouse_on_tools]
## treats any visible Control of the main canvas under the mouse as "mouse on UI", and this one is always near the mouse
class_name HexNameTooltip extends PanelContainer

@export var editor: HexMapEditor
## Distance from the mouse so the tooltip doesnt sit under the cursor sprite
@export var mouse_offset: Vector2 = Vector2(20, 20)

@onready var name_label: Label = %HexNameLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# checked every frame since the hex under the mouse changes with mouse motion, camera pan/zoom and name edits
func _process(_delta: float) -> void:
	var hex_name: String = _get_hovered_hex_name()
	if hex_name.is_empty():
		visible = false
		return

	if name_label.text != hex_name:
		name_label.text = hex_name
		reset_size() # shrinks back when going from a long name to a short one
	visible = true
	_follow_mouse()


## Returns the name of the hex under the mouse, or an empty string if it has none (or the mouse is on the UI)
func _get_hovered_hex_name() -> String:
	if editor == null or GlobalEditorData.hex_data_store == null:
		return ""
	if editor.is_mouse_on_tools():
		return ""

	# every layer shares the pencil tileset and scale, so its coords are the same as any layer
	var pencil: TileMapLayer = editor.pencil_tilemap
	if pencil.tile_set == null:
		return ""

	var tile_coord: Vector2i = pencil.local_to_map(pencil.to_local(editor.get_global_mouse_position()))
	var hex_data: HexData = GlobalEditorData.hex_data_store.get_hex(tile_coord)
	if hex_data == null:
		return ""
	return hex_data.hex_name.strip_edges()


func _follow_mouse() -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport_rect().size
	var target: Vector2 = mouse_pos + mouse_offset

	# flips to the other side of the mouse when it would go off screen
	if target.x + size.x > viewport_size.x:
		target.x = mouse_pos.x - mouse_offset.x - size.x
	if target.y + size.y > viewport_size.y:
		target.y = mouse_pos.y - mouse_offset.y - size.y

	position = target
