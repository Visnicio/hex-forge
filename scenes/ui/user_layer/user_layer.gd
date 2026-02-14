## A layer container that the user can interact with, trick thing, we use the LayersButtonGroup resource to handle selecting a single layer
class_name UserLayer extends HBoxContainer

@export var layer_name: String
@export var layer_tilemap_ref: TileMapLayer
@export var checkbox: CheckBox
@export var delete_button: Button
## A reference to its button group, used to fire a global signal when a new layer is selected
@export var layers_button_group: ButtonGroup


func _ready() -> void:
	checkbox.text = layer_name
	layers_button_group.pressed.connect(func(new_button_pressed: BaseButton):
		if new_button_pressed == checkbox:
			SignalBus.layer_selected.emit(self)
		)
