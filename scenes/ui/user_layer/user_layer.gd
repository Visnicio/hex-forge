## A layer container that the user can interact with, trick thing, we use the LayersButtonGroup resource to handle selecting a single layer
class_name UserLayer extends HBoxContainer

@export var layer_name: String:
	set(new_value):
		layer_name = new_value
		checkbox.text = new_value
@export var layer_tilemap_ref: TileMapLayer
@export var checkbox: CheckBox
@export var delete_button: Button
## A reference to its button group, used to fire a global signal when a new layer is selected
@export var layers_button_group: ButtonGroup
@export var move_up_button: Button
@export var move_down_button: Button
@export var rename_button: Button

var rename_modal: InputModal = null

func _ready() -> void:
	checkbox.text = layer_name
	layers_button_group.pressed.connect(func(new_button_pressed: BaseButton):
		if new_button_pressed == checkbox:
			SignalBus.layer_selected.emit(self)
		)
	
	move_up_button.pressed.connect(func():
		SignalBus.layer_reorder_requested.emit(self, -1)
		)
	move_down_button.pressed.connect(func():
		SignalBus.layer_reorder_requested.emit(self, 1) # descend index
		)
		
	rename_button.pressed.connect(func():
		rename_modal = Utils.input_modal("Rename Layer", GlobalEditorData.main_canvas, layer_name)
		rename_modal.size.x = 256
		rename_modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		rename_modal.value_changed.connect(func(new_input_value: String):
			layer_name = new_input_value
			)
		)
