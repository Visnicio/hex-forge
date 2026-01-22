class_name HexMapEditor
extends Node2D

enum MapLayer {
	WORLD,
	DECAL
}

@export var tileset_picker_button: Button
@export var tiles_grid_container: GridContainer
@export var tools_container: Control
@export var map_name_input: LineEdit
@export var camera_input: CameraInput

@export var main_background: ColorRect
@export var camera: Camera2D

## Used to check if mouse is in UI
@export var main_panels: Array[MarginContainer] 

@export_group("Tilemaps")
@export var world_tilemap: TileMapLayer
@export var decals_tilemap: TileMapLayer
@export var pencil_tilemap: TileMapLayer

@export_group("Layers")
@export var world_layer_checkbox: CheckBox
@export var decals_layer_checkbox: CheckBox

@export_group("UI")
@export var main_canvas: CanvasLayer
@export var tileset_picker_modal: TileSetPickerModal
@export var controls_button: Button
@export var controls_panel: Panel


## Holds the coords for the current selected tile to query it on the tileset, set it to (-1,-1) to clear the pencil
var current_selected_tile_coords: Vector2i = Vector2i(-1, -1)
## current tile source id in case the tileset has more than one souce
var current_selected_tile_source_id: int = -1
## Current TileMapLayer selected
var current_selected_layer: TileMapLayer
## current tileset config file, ex: "res://resources/definitions/tilesets/example_tileset.json"
var current_tileset_config_file: String = ""

## Used for registering last actions by user so we can undo
var undo_redo = UndoRedo.new()

# Variable to store the current stroke history: { coords: {source_id, atlas_coords} }
var _current_stroke_buffer: Dictionary = {}
var _is_painting: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tileset_picker_button.pressed.connect(_on_tileset_picker_button_pressed)
	
	world_layer_checkbox.pressed.connect(_on_world_layer_check_pressed)
	decals_layer_checkbox.pressed.connect(_on_decal_layer_check_pressed)
	
	controls_button.pressed.connect(func():
		controls_panel.show()
		)
	
	tileset_picker_modal.config_changed.connect(func(new_tileset: String):
		if tileset_picker_modal.tilesets.has(new_tileset):
			var data = tileset_picker_modal.tilesets[new_tileset]
			print(data)
			current_tileset_config_file = data.file_path
			load_tileset_for_map(tileset_picker_modal.tilesets[new_tileset].tileset_resource, data)
		)
	
	current_selected_layer = world_tilemap
	
	# clear defaults
	clear_maps()

func _process(_delta: float) -> void:
	main_background.global_position = camera.get_screen_center_position() - main_background.get_rect().size / 2 # hacky to keep the background on screen but behind canvas layer
	
	pencil_tilemap.clear()
	if current_selected_tile_coords != Vector2i(-1, -1) and current_selected_tile_source_id != -1:
		var mouse_pos = pencil_tilemap.to_local(get_global_mouse_position())
		pencil_tilemap.set_cell(pencil_tilemap.local_to_map(mouse_pos), current_selected_tile_source_id, current_selected_tile_coords)

func _input(event: InputEvent) -> void:
	# 1. Check basic states (mouse on tools, typing, etc.)
	var is_typing_name: bool = map_name_input.get_global_rect().has_point(get_viewport().get_mouse_position())
	if is_mouse_on_tools() or is_typing_name or current_selected_tile_coords == Vector2i(-1, -1):
		return

	# --- Painting Logic (Left Button) ---
	if Input.is_action_just_pressed("left_click"):
		_start_stroke()
		_paint_at_mouse() # Paint the first tile (single click)
	
	elif Input.is_action_pressed("left_click") and _is_painting:
		_paint_at_mouse() # Paint while dragging
		
	elif Input.is_action_just_released("left_click") and _is_painting:
		_commit_stroke("Add Tile", false) # Finish and save to UndoRedo

	# --- Erasing Logic (Right Button) ---
	if Input.is_action_just_pressed("right_click"):
		_start_stroke()
		_erase_at_mouse()
		
	elif Input.is_action_pressed("right_click") and _is_painting:
		_erase_at_mouse()
		
	elif Input.is_action_just_released("right_click") and _is_painting:
		_commit_stroke("Remove Tile", true)

	# --- Undo / Redo ---
	if Input.is_action_just_pressed("redo"):
		undo_redo.redo()
	elif Input.is_action_just_pressed("undo"):
		undo_redo.undo()
		
	# handles focus from nodes
	if Input.is_action_just_pressed("left_click") or Input.is_key_pressed(KEY_ESCAPE):
		get_viewport().gui_release_focus()
		
	# deselect current pencil on esc
	if Input.is_key_pressed(KEY_ESCAPE) and current_selected_tile_coords != Vector2i(-1, -1):
		deselect_current_pencil()

func _on_tileset_picker_button_pressed() -> void:
	tileset_picker_modal.show()


func _create_tile_button(button_texture: Texture2D, buttons_container: GridContainer, original_tile_coords: Vector2i, tile_source_id: int) -> void:
	var new_button: TextureButton = TextureButton.new()
	new_button.texture_normal = button_texture
	new_button.ignore_texture_size = true
	new_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	new_button.custom_minimum_size = Vector2(64, 64) 
	
	new_button.pressed.connect(func():
		current_selected_tile_coords = original_tile_coords
		current_selected_tile_source_id = tile_source_id
		print("pressed button: ", original_tile_coords)
	)
	
	buttons_container.add_child(new_button)


func load_tileset_for_map(tileset_resource_path: String, tileset_config_data: Dictionary) -> void:
	deselect_current_pencil()
	for child in tiles_grid_container.get_children():
		child.queue_free()
	
	# load the tileset
	var loaded_tileset: TileSet = load(tileset_resource_path)
	pencil_tilemap.tile_set = loaded_tileset
	world_tilemap.tile_set = loaded_tileset
	decals_tilemap.tile_set = loaded_tileset
	
	if tileset_config_data != null: # retro compatible with older saves
		if tileset_config_data.has("tilemap_scale"):
			pencil_tilemap.scale = Vector2(tileset_config_data.tilemap_scale,tileset_config_data.tilemap_scale)
			world_tilemap.scale = Vector2(tileset_config_data.tilemap_scale,tileset_config_data.tilemap_scale)
			decals_tilemap.scale = Vector2(tileset_config_data.tilemap_scale,tileset_config_data.tilemap_scale)
		else:
			pencil_tilemap.scale = Vector2.ONE
			world_tilemap.scale = Vector2.ONE
			decals_tilemap.scale = Vector2.ONE
	
	#get its source
	for i: int in loaded_tileset.get_source_count():
		var tileset_source: TileSetSource = loaded_tileset.get_source(i)
		if tileset_source == null: continue
		
		var rows: int = tileset_source.get_atlas_grid_size().y
		# but it is 1-indexed, so I need to subtract -1 to query i coords
		var cols: int = tileset_source.get_atlas_grid_size().x
		
		if tileset_source is TileSetAtlasSource: # if selected is a source
			for row in rows:
				for col in cols:
					var tile_coord: Vector2i = Vector2i(col, row)
					
					# for each tile in tileset, check if its set to usable
					if !tileset_source.has_tile(tile_coord): continue
					
					# creates a new atlas to hold the tile texture
					var atlas: AtlasTexture = AtlasTexture.new()
					atlas.atlas = tileset_source.texture
					atlas.region = tileset_source.get_tile_texture_region(tile_coord)
					
					# creates the button
					_create_tile_button(atlas, tiles_grid_container, tile_coord, i)


func clear_maps() -> void:
	world_tilemap.clear()
	world_tilemap.tile_set = null
	pencil_tilemap.clear()
	pencil_tilemap.tile_set = null
	decals_tilemap.clear()
	decals_tilemap.tile_set = null


func _on_world_layer_check_pressed() -> void:
	decals_layer_checkbox.button_pressed = false
	current_selected_layer = world_tilemap

func _on_decal_layer_check_pressed() -> void:
	world_layer_checkbox.button_pressed = false
	current_selected_layer = decals_tilemap

func is_mouse_on_tools() -> bool:
	
	for panel: MarginContainer in main_panels:
		if panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
			return true
	
	return false


func deselect_current_pencil() -> void:
	current_selected_tile_coords = Vector2i(-1, -1)

func is_pencil_selected() -> bool:
	return current_selected_tile_coords != Vector2i(-1, -1)


# Starts the stroke (clears the buffer)
func _start_stroke():
	_is_painting = true
	_current_stroke_buffer.clear()

# Paints visually and saves the old state to the buffer
func _paint_at_mouse():
	var mouse_pos = current_selected_layer.local_to_map(world_tilemap.to_local(get_global_mouse_position()))
	
	# Optimization: If we already painted this tile IN THIS STROKE with the SAME value, ignore
	var current_source = current_selected_layer.get_cell_source_id(mouse_pos)
	var current_atlas = current_selected_layer.get_cell_atlas_coords(mouse_pos)
	
	# If the tile is already what we want to paint, return
	if current_source == current_selected_tile_source_id and current_atlas == current_selected_tile_coords:
		return

	# Save the OLD tile state (for Undo) if we haven't saved it in this stroke yet
	if not _current_stroke_buffer.has(mouse_pos):
		_current_stroke_buffer[mouse_pos] = {
			"source": current_source,
			"atlas": current_atlas
		}
	
	# Apply the change visually NOW (without waiting for undo_redo)
	current_selected_layer.set_cell(mouse_pos, current_selected_tile_source_id, current_selected_tile_coords)

# Erase visually and store state
func _erase_at_mouse():
	var mouse_pos = current_selected_layer.local_to_map(world_tilemap.to_local(get_global_mouse_position()))
	
	var current_source = current_selected_layer.get_cell_source_id(mouse_pos)
	if current_source == -1: return # Already empty
	
	if not _current_stroke_buffer.has(mouse_pos):
		_current_stroke_buffer[mouse_pos] = {
			"source": current_source,
			"atlas": current_selected_layer.get_cell_atlas_coords(mouse_pos)
		}
		
	current_selected_layer.set_cell(mouse_pos, -1, Vector2i(-1, -1))

# Finalizes the stroke and creates the UndoRedo action
func _commit_stroke(action_name: String, is_erasing: bool):
	_is_painting = false
	
	if _current_stroke_buffer.is_empty():
		return # Nothing changed, don't create undo
		
	undo_redo.create_action(action_name)
	
	# DO METHOD: Redo what we just painted
	# Since we already painted visually, the 'redo' needs to ensure it stays painted
	for cell_pos in _current_stroke_buffer.keys():
		if is_erasing:
			undo_redo.add_do_method(current_selected_layer.set_cell.bind(cell_pos, -1, Vector2i(-1, -1)))
		else:
			undo_redo.add_do_method(current_selected_layer.set_cell.bind(cell_pos, current_selected_tile_source_id, current_selected_tile_coords))
			
	# UNDO METHOD: Restore what was in the buffer
	for cell_pos in _current_stroke_buffer.keys():
		var old_data = _current_stroke_buffer[cell_pos]
		undo_redo.add_undo_method(current_selected_layer.set_cell.bind(cell_pos, old_data["source"], old_data["atlas"]))
		
	# Commit the action. No need to execute (false) because we already visually changed it during input.
	undo_redo.commit_action(false)
