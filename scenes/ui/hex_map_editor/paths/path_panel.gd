## Bottom panel with the road/river tools and the data of the selected path (name, style, description,
## and when the tileset has road/river tiles: how it is drawn and which hexes had no matching tile).[br]
## Name and description are written straight into the live [PathData] (no undo, like the hex data panel);
## style, draw mode and tiles picked by hand go through [method PathTools.commit_edit] so they can be undone
class_name PathPanel extends PanelContainer

const MODES: PackedStringArray = ["auto", "vector", "tile"]
## Gap between the panel and the bottom of the screen (room for the map size label and the badges toggle)
const BOTTOM_MARGIN: float = 44.0
const MODE_LABELS: PackedStringArray = ["Auto", "Vector", "Tiles"]

@export var path_tools: PathTools

@onready var road_button: Button = %RoadButton
@onready var river_button: Button = %RiverButton
@onready var select_button: Button = %SelectButton
@onready var erase_button: Button = %EraseButton
@onready var river_centers_check: CheckBox = %RiverCentersCheck
@onready var anchor_layer_option: OptionButton = %AnchorLayerOption
@onready var map_mode_option: OptionButton = %MapModeOption
@onready var details: VBoxContainer = %Details
@onready var path_name: LineEdit = %PathName
@onready var style_option: OptionButton = %StyleOption
@onready var delete_button: Button = %DeletePathButton
@onready var close_button: Button = %ClosePathButton
@onready var path_description: TextEdit = %PathDescription
@onready var path_mode_option: OptionButton = %PathModeOption
@onready var tile_status: Label = %TileStatus
@onready var missing_row: HBoxContainer = %MissingRow
@onready var missing_cell_option: OptionButton = %MissingCellOption
@onready var vector_here_button: Button = %VectorHereButton
@onready var clear_picks_button: Button = %ClearPicksButton
@onready var tile_choices: HFlowContainer = %TileChoices

var _current_path_id: String = ""
var _tool_buttons: Dictionary[Button, int] = {}
var _layers_signature: String = ""
## Hex picked in the "missing tiles" list, tiles picked below go to it
var _selected_cell: Variant = null


func _ready() -> void:
	_tool_buttons = {
		road_button: GlobalEditorData.EditorTool.ROAD,
		river_button: GlobalEditorData.EditorTool.RIVER,
		select_button: GlobalEditorData.EditorTool.PATH_SELECT,
		erase_button: GlobalEditorData.EditorTool.PATH_ERASE,
	}
	for button: Button in _tool_buttons.keys():
		button.toggled.connect(_on_tool_button_toggled.bind(button))

	for i: int in MODES.size():
		map_mode_option.add_item(MODE_LABELS[i])
		path_mode_option.add_item(MODE_LABELS[i])

	SignalBus.tool_changed.connect(_on_tool_changed)
	SignalBus.path_selected.connect(_on_path_selected)
	SignalBus.path_dismissed.connect(_on_path_dismissed)

	river_centers_check.toggled.connect(func(on: bool) -> void:
		path_tools.river_anchor = PathData.Anchor.CELL if on else PathData.Anchor.VERTEX)
	anchor_layer_option.item_selected.connect(_on_anchor_layer_selected)
	map_mode_option.item_selected.connect(func(index: int) -> void: path_tools.path_store.render_mode = MODES[index])

	path_name.text_changed.connect(_on_name_changed)
	path_description.text_changed.connect(_on_description_changed)
	style_option.item_selected.connect(_on_style_selected)
	path_mode_option.item_selected.connect(_on_path_mode_selected)
	delete_button.pressed.connect(func() -> void: path_tools.delete_path(_current_path_id))
	close_button.pressed.connect(SignalBus.path_dismissed.emit)
	missing_cell_option.item_selected.connect(_on_missing_cell_selected)
	vector_here_button.pressed.connect(_on_vector_here_pressed)
	clear_picks_button.pressed.connect(_on_clear_picks_pressed)

	var store: PathStore = path_tools.path_store
	store.path_changed.connect(func(path_id: String) -> void:
		if path_id != _current_path_id:
			return
		if store.has_path(path_id):
			_refresh_details() # undo/redo of a style or mode change
		else:
			SignalBus.path_dismissed.emit())
	store.store_reset.connect(func() -> void: _layers_signature = "")
	_fit_to_content.call_deferred()
	path_tools.paths_layer.tiles_rebuilt.connect(func() -> void:
		if _current_path_id != "":
			_refresh_tile_section())


# the layer list and the map mode change without a signal (add/rename/reorder/delete, map loaded), cheap to check
func _process(_delta: float) -> void:
	_refresh_anchor_layers()
	var mode_index: int = MODES.find(path_tools.path_store.render_mode)
	if mode_index != -1 and map_mode_option.selected != mode_index:
		map_mode_option.select(mode_index)


## Keeps the panel centered and glued to the bottom while its content grows/shrinks
## (reset_size() would keep the top where it was, so the panel crept up every time the details closed)
func _fit_to_content() -> void:
	var minimum: Vector2 = get_combined_minimum_size()
	offset_left = -minimum.x / 2.0
	offset_right = minimum.x / 2.0
	offset_bottom = -BOTTOM_MARGIN
	offset_top = -BOTTOM_MARGIN - minimum.y


func _on_tool_button_toggled(pressed: bool, button: Button) -> void:
	if pressed:
		GlobalEditorData.set_active_tool(_tool_buttons[button])
	elif GlobalEditorData.active_tool == _tool_buttons[button]:
		GlobalEditorData.set_active_tool(GlobalEditorData.EditorTool.NONE)


## Keeps the buttons in sync when the tool changes from somewhere else (pencil picked, ESC, marker placing)
func _on_tool_changed(new_tool: int) -> void:
	for button: Button in _tool_buttons.keys():
		button.set_pressed_no_signal(_tool_buttons[button] == new_tool)


func _on_path_selected(path_id: String) -> void:
	if path_tools.path_store.get_path_data(path_id) == null:
		return
	if path_id != _current_path_id:
		_selected_cell = null
	_current_path_id = path_id
	_refresh_details()
	details.visible = true


func _refresh_details() -> void:
	var path: PathData = _current_path()
	if path == null:
		return
	if path_name.text != path.path_name:
		path_name.text = path.path_name
	if path_description.text != path.description:
		path_description.text = path.description

	style_option.clear()
	for style: PathStyle in PathStyles.styles_for(path.kind):
		style_option.add_item(style.display_name)
		style_option.set_item_metadata(style_option.item_count - 1, style.id)
		if style.id == PathStyles.resolve(path.style_id, path.kind).id:
			style_option.select(style_option.item_count - 1)
	path_mode_option.select(maxi(MODES.find(path.render_mode), 0))
	_refresh_tile_section()


func _on_path_dismissed() -> void:
	_current_path_id = ""
	_selected_cell = null
	path_name.release_focus()
	path_description.release_focus()
	details.visible = false
	_fit_to_content.call_deferred() # shrinks back to only the tools row


func _current_path() -> PathData:
	return path_tools.path_store.get_path_data(_current_path_id)


func _on_name_changed(new_text: String) -> void:
	var path: PathData = _current_path()
	if path != null:
		path.path_name = new_text


func _on_description_changed() -> void:
	var path: PathData = _current_path()
	if path != null:
		path.description = path_description.text


func _on_style_selected(index: int) -> void:
	var style_id: String = str(style_option.get_item_metadata(index))
	path_tools.commit_edit(_current_path_id, "Change Path Style", func(path: PathData) -> void: path.style_id = style_id)


func _on_path_mode_selected(index: int) -> void:
	path_tools.commit_edit(_current_path_id, "Change Path Mode", func(path: PathData) -> void: path.render_mode = MODES[index])


# --- tiles ---

## Status of how the path is drawn, plus the list of hexes without a matching tile
func _refresh_tile_section() -> void:
	var path: PathData = _current_path()
	if path == null:
		return
	var paths_layer: PathsLayer = path_tools.paths_layer
	var index: TerrainMaskIndex = paths_layer.index_for(path.kind)
	var uses_tiles: bool = paths_layer.effective_mode(path) == "tile"

	if uses_tiles:
		var missing: Dictionary = paths_layer.missing_tiles_of(path)
		tile_status.text = "Tileset tiles" if missing.is_empty() else "Tileset tiles, %d hex(es) in vector" % missing.size()
	elif index == null:
		tile_status.text = "Vector (tileset has no %s tiles)" % PathData.KIND_NAMES[path.kind]
	elif path.anchor != PathData.Anchor.CELL:
		tile_status.text = "Vector (tiles need a river by centers)"
	else:
		tile_status.text = "Vector"

	var cells: Dictionary = {}
	if uses_tiles:
		var missing: Dictionary = paths_layer.missing_tiles_of(path)
		for cell: Vector2i in missing.keys():
			var info: Dictionary = missing[cell]
			cells[cell] = "vector by hand" if info.forced else "needs " + index.describe(info.mask)
		for key: String in path.tile_exceptions.keys():
			var cell: Variant = str_to_var("Vector2i" + key)
			if cell is Vector2i and not cells.has(cell):
				cells[cell] = "tile picked by hand"

	missing_row.visible = not cells.is_empty()
	missing_cell_option.clear()
	var selected_index: int = -1
	for cell: Vector2i in cells.keys():
		missing_cell_option.add_item("%s: %s" % [cell, cells[cell]])
		missing_cell_option.set_item_metadata(missing_cell_option.item_count - 1, cell)
		if _selected_cell == cell:
			selected_index = missing_cell_option.item_count - 1
	if selected_index == -1 and missing_cell_option.item_count > 0:
		selected_index = 0
		_selected_cell = missing_cell_option.get_item_metadata(0)
	elif selected_index == -1:
		_selected_cell = null
	if selected_index != -1:
		missing_cell_option.select(selected_index)
	clear_picks_button.disabled = path.tile_exceptions.is_empty()
	_fill_tile_choices(index if missing_row.visible else null)
	_fit_to_content.call_deferred()


func _on_missing_cell_selected(index: int) -> void:
	_selected_cell = missing_cell_option.get_item_metadata(index)


func _fill_tile_choices(index: TerrainMaskIndex) -> void:
	for child: Node in tile_choices.get_children():
		child.queue_free()
	tile_choices.visible = index != null
	if index == null:
		return
	for entry: Dictionary in index.entries():
		var source: TileSetAtlasSource = index.tile_set.get_source(entry.source_id) as TileSetAtlasSource
		var data: TileData = source.get_tile_data(entry.atlas_coords, entry.alternative)
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = source.texture
		atlas.region = source.get_tile_texture_region(entry.atlas_coords)
		var button: TextureButton = TextureButton.new()
		button.texture_normal = atlas
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(40, 48)
		button.flip_h = data.flip_h
		button.flip_v = data.flip_v
		button.tooltip_text = "Use this tile on the selected hex (%s)" % index.describe(entry.mask)
		button.pressed.connect(_on_tile_choice_pressed.bind(entry))
		tile_choices.add_child(button)


func _on_tile_choice_pressed(entry: Dictionary) -> void:
	if _selected_cell == null:
		return
	var key: String = str(_selected_cell)
	path_tools.commit_edit(_current_path_id, "Pick Path Tile", func(path: PathData) -> void:
		path.tile_exceptions[key] = TilePathRenderer.tile_exception(entry))


func _on_vector_here_pressed() -> void:
	if _selected_cell == null:
		return
	var key: String = str(_selected_cell)
	path_tools.commit_edit(_current_path_id, "Path Hex To Vector", func(path: PathData) -> void:
		path.tile_exceptions[key] = {"vector": true})


func _on_clear_picks_pressed() -> void:
	path_tools.commit_edit(_current_path_id, "Clear Picked Tiles", func(path: PathData) -> void: path.tile_exceptions = {})


# --- anchor layer ---

func _refresh_anchor_layers() -> void:
	if GlobalEditorData.user_layers == null:
		return
	var anchor: UserLayer = path_tools.paths_layer.find_anchor_layer()
	var names: PackedStringArray = []
	for layer: UserLayer in GlobalEditorData.user_layers.get_all_layers():
		if is_instance_valid(layer):
			names.append(layer.layer_name)
	var signature: String = ",".join(names) + "|" + (anchor.layer_name if anchor else "")
	if signature == _layers_signature:
		return
	_layers_signature = signature

	anchor_layer_option.clear()
	for layer_name: String in names:
		anchor_layer_option.add_item(layer_name)
		if anchor != null and layer_name == anchor.layer_name:
			anchor_layer_option.select(anchor_layer_option.item_count - 1)


func _on_anchor_layer_selected(index: int) -> void:
	path_tools.path_store.anchor_layer = anchor_layer_option.get_item_text(index)
