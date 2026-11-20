## Panel to view and edit the HexData of the selected hex.[br]
## Edits are written straight into the HexData inside the HexDataStore (its a reference),
## so theres no "apply" step, it gets saved with the map like everything else
class_name HexDataPanel extends Panel

@onready var hex_name: LineEdit = %HexName
@onready var hex_freetext: TextEdit = %HexFreetext
@onready var close_button: Button = %CloseHexDataButton
@onready var panel_name: Label = %PanelName

## Hex currently shown on the panel, only valid while [member _has_hex_open] is true
var _current_coord: Vector2i
var _has_hex_open: bool = false


func _ready() -> void:
	visible = false
	offset_transform_scale = Vector2.ZERO

	# goes through the bus so anything else listening also knows the hex was closed
	close_button.pressed.connect(SignalBus.hex_dismissed.emit)

	SignalBus.hex_selected.connect(_on_hex_selected)
	SignalBus.hex_dismissed.connect(_on_hex_dismissed)

	hex_name.text_changed.connect(_on_hex_name_changed)
	hex_freetext.text_changed.connect(_on_hex_freetext_changed)


func _on_hex_selected(position_in_tile_coords: Vector2i) -> void:
	# marks the hex as open before touching the fields, since setting their text can fire text_changed
	_current_coord = position_in_tile_coords
	_has_hex_open = true

	# only reads here, the HexData gets created on the first edit, so just clicking around
	# the map doesnt fill the store with empty hexes
	var hex_data: HexData = GlobalEditorData.hex_data_store.get_hex(position_in_tile_coords)
	panel_name.text = "Hex Data - " + str(position_in_tile_coords)
	hex_name.text = hex_data.hex_name if hex_data else ""
	hex_freetext.text = hex_data.hex_freetext if hex_data else ""

	show_panel()


func _on_hex_dismissed() -> void:
	_has_hex_open = false
	hex_name.release_focus()
	hex_freetext.release_focus()
	hide_panel()


func _on_hex_name_changed(new_text: String) -> void:
	var hex_data: HexData = _get_or_create_current_hex()
	if hex_data == null: return
	hex_data.hex_name = new_text
	GlobalEditorData.hex_data_store.notify_changed(_current_coord)


func _on_hex_freetext_changed() -> void:
	var hex_data: HexData = _get_or_create_current_hex()
	if hex_data == null: return
	hex_data.hex_freetext = hex_freetext.text
	GlobalEditorData.hex_data_store.notify_changed(_current_coord)


## Returns null when theres no hex open, avoids writing into a hex while the panel is closing
func _get_or_create_current_hex() -> HexData:
	if not _has_hex_open:
		return null
	return GlobalEditorData.hex_data_store.get_or_create_hex(_current_coord)


func show_panel() -> void:
	visible = true
	var t: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(self, "offset_transform_scale", Vector2.ONE, .3).from_current()


func hide_panel() -> void:
	var t: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "offset_transform_scale", Vector2.ZERO, .3).from_current()
	t.tween_callback(func():
		visible = false
	)
