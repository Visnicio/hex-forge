class_name LayerCheckboxContainer extends HBoxContainer

@export var layer_name: String
@export var layer_tilemap_ref: TileMapLayer
@export var checkbox: CheckBox
@export var delete: Button

func _ready() -> void:
	checkbox.text = layer_name
	SignalBus.layer_selected.connect(func(container_selected: LayerCheckboxContainer):
		if container_selected == self:
			checkbox.button_pressed = true
		else:
			checkbox.button_pressed = false
		)
