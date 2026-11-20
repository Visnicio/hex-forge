class_name HexDataPanel extends Panel

@onready var hex_freetext: TextEdit = %HexFreetext
@onready var close_button: Button = %CloseHexDataButton
@onready var panel_name: Label = %PanelName

func _ready() -> void:
	visible = false
	offset_transform_scale = Vector2.ZERO
	close_button.pressed.connect(func():
		hide_panel()
	)
	
	SignalBus.hex_dismissed.connect(hide_panel)
	SignalBus.hex_selected.connect(func(position_in_tile_coords: Vector2i):
		panel_name.text = "Hex Data - " + str(position_in_tile_coords)
		show_panel()
	)


func _process(delta: float) -> void:
	pass


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
