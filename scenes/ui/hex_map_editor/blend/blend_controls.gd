## Bottom right controls of the biome smoothing and coastlines (user preferences, never saved in the map)
class_name BlendControls extends PanelContainer

@export var ground_blend: GroundBlend

@onready var smooth_toggle: CheckButton = %SmoothToggle
@onready var intensity_slider: HSlider = %IntensitySlider
@onready var coast_toggle: CheckButton = %CoastToggle


func _ready() -> void:
	# the UI is earlier in the tree, so the blend loads its saved preferences after this _ready
	sync_from_blend.call_deferred()

	smooth_toggle.toggled.connect(func(on: bool) -> void:
		ground_blend.enabled = on
		intensity_slider.editable = on)
	intensity_slider.value_changed.connect(func(value: float) -> void: ground_blend.intensity = value)
	coast_toggle.toggled.connect(func(on: bool) -> void: ground_blend.coastlines = on)


func sync_from_blend() -> void:
	smooth_toggle.set_pressed_no_signal(ground_blend.enabled)
	intensity_slider.set_value_no_signal(ground_blend.intensity)
	intensity_slider.editable = ground_blend.enabled
	coast_toggle.set_pressed_no_signal(ground_blend.coastlines)
