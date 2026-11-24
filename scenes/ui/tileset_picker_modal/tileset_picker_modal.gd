## Modal UI that lets the user select which tileset to use for the map editor.
## [br][br]
## Aggregates tilesets from two sources in order:[br]
## 1. Built-in samples shipped with the game under [code]res://samples/[/code].[br]
## 2. User-installed mods loaded at runtime by [ModLoader] from [code]user://tilesets/[/code].[br]
## [br]
## After both sources are merged into [member tilesets], the modal populates the
## [member tileset_picker] dropdown and emits [signal config_changed] whenever
## the player picks a different entry.
class_name TileSetPickerModal extends Control

## Emitted when the player selects a tileset from the dropdown.
## [br][code]new_tileset_title[/code] is the key in [member tilesets] for the chosen
## [MapTilesetConfiguration], or [code]"None"[/code] when the blank entry is selected.
signal config_changed(new_tileset_title: String)

## All selectable tilesets, keyed by [member MapTilesetConfiguration.tileset_name].
## Populated in [method _ready] from built-in samples and then merged with
## [member ModLoader.mod_tilesets].
var tilesets: Dictionary[String, MapTilesetConfiguration] = {}

## The [OptionButton] node used to display and select tilesets.
@export var tileset_picker: OptionButton

func _ready() -> void:
	hide()
	load_samples_tilesets()
	get_mods_tilesets()
	tileset_picker.add_item("None")

	# Populate the dropdown with every collected tileset name.
	for tileset_name in tilesets.keys():
		tileset_picker.add_item(tileset_name)

	tileset_picker.item_selected.connect(func(index: int):
		var selected_title = tileset_picker.get_item_text(index)
		if tilesets.has(selected_title):
			config_changed.emit(selected_title)
		else:
			config_changed.emit("None")
		hide()
	)

	$Close.pressed.connect(func():
		hide()
		)

	_add_mod_check_button()


## "Check mod" shows what the selected tileset provides for roads/rivers/smoothing (see [ModLint])
func _add_mod_check_button() -> void:
	var dialog: ModLintDialog = ModLintDialog.new()
	add_child(dialog)
	var button: Button = Button.new()
	button.text = "Check mod"
	button.tooltip_text = "What this tileset provides for roads, rivers and biome smoothing, and what falls back"
	tileset_picker.get_parent().add_child(button)
	button.pressed.connect(func() -> void:
		var selected: String = tileset_picker.get_item_text(tileset_picker.selected) if tileset_picker.selected >= 0 else ""
		var config: MapTilesetConfiguration = tilesets.get(selected, null)
		if config == null and GlobalEditorData.map_editor_ref != null:
			config = GlobalEditorData.map_editor_ref.current_map_tileset_configuration
		dialog.show_for(config))


## Scans [code]res://samples/[/code] and loads every [MapTilesetConfiguration] found there
## into [member tilesets]. Skips hidden files, [code].import[/code] sidecars, and
## [code].md[/code] files. Strips the [code].remap[/code] extension when running from an
## exported build, where Godot renames resources to [code]<name>.remap[/code].
func load_samples_tilesets() -> void:
	var tilesets_dir: String = "res://samples"
	var dir = DirAccess.open(tilesets_dir)
	if not dir:
		push_error("Could not find sample tilesets dir")

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if !file_name.begins_with(".") and !file_name.ends_with(".import") and !file_name.ends_with(".md"):
			var full_path = tilesets_dir + "/" + file_name

			# Strip .remap — present in exported builds where resources are renamed.
			if full_path.ends_with(".remap"):
				full_path = full_path.substr(0, full_path.length() - 6)

			var loaded_config: MapTilesetConfiguration = load(full_path)
			if loaded_config != null:
				tilesets[loaded_config.tileset_name] = loaded_config
			else:
				push_error("Error parsing save file JSON: ", file_name)

		file_name = dir.get_next()
	dir.list_dir_end()


## Merges [member ModLoader.mod_tilesets] into [member tilesets].
## Must be called after [method load_samples_tilesets] so that mod entries that share a
## name with a built-in sample overwrite the built-in rather than being silently discarded.
func get_mods_tilesets() -> void:
	tilesets.merge(ModLoader.mod_tilesets)
	print_debug(tilesets)
