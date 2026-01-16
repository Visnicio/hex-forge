extends Node

enum State {
	SAVING,
	LOADING
}

@export var map_file_dialog: FileDialog
@export var new_map_button: Button
@export var save_map_button: Button
@export var load_map_button: Button
@export var export_map_button: Button
@export var map_name_input: LineEdit
@export var main_canvas: CanvasLayer

@export_group("Markers")
@export var markers: MarkersManager
@export var world_marker_scene: PackedScene

var editor: HexMapEditor
var current_state: State = State.LOADING
var last_map_loaded_path: String = ""

func _ready() -> void:
	editor = get_parent() as HexMapEditor
	
	map_file_dialog.add_filter("*.json", "Map Files")
	
	export_map_button.pressed.connect(func():
		export_tilemap_to_png(editor.world_tilemap, "res://test.png")
		)
	
	new_map_button.pressed.connect(_on_new_map_pressed)
	
	load_map_button.pressed.connect(func():
		current_state = State.LOADING
		map_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		map_file_dialog.show()
		)
	
	save_map_button.pressed.connect(func():
		current_state = State.SAVING
		map_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		map_file_dialog.show()
		)
		
	
	
	map_file_dialog.file_selected.connect(on_file_selected)

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("shortcut_save"):
		if last_map_loaded_path != "":
			print_debug("Quicksaving: ", last_map_loaded_path)
			current_state = State.SAVING
			map_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			map_file_dialog.show()


func _on_new_map_pressed() -> void:
	editor.clear_maps()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	markers.clear_all_markers()


func on_file_selected(map_path: String) -> void:
	if current_state == State.SAVING:
		save_current_map(map_path, editor.current_tileset_config_file)
		
	elif current_state == State.LOADING:
		load_map_into_editor(map_path);


func load_map_into_editor(map_path: String) -> void:
	editor.clear_maps()
	markers.clear_all_markers()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	
	var map_data: Dictionary = SaveManager.load_map(map_path)
	map_name_input.text = map_data.get("map_name", "No Name Saved")
	var map_config_data = {}
	if map_data.has("tileset_config_file"):
		map_config_data = Utils.get_json_data(map_data.get("tileset_config_file")) 
	editor.load_tileset_for_map(map_data.get("tileset_resource_path"), map_config_data)
	
	# load world map
	for cell_data_key: String in map_data.world_map.cells.keys():
		var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
		var cell_data: Dictionary = map_data.world_map.cells[cell_data_key]
		var source_id: int = 0
		if cell_data.has("source_id"): # Retro Compatible with older saves
			source_id = cell_data.get("source_id")
		editor.world_tilemap.set_cell(key_as_vector, source_id, str_to_var("Vector2i"+cell_data.atlas_coords))
	
	# load decals map
	if !map_data.has("decals_map"): return
	for cell_data_key: String in map_data.decals_map.cells.keys():
		var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
		var cell_data: Dictionary = map_data.decals_map.cells[cell_data_key]
		var source_id: int = 0
		if cell_data.has("source_id"): # Retro Compatible with older saves
			source_id = cell_data.get("source_id")
		editor.decals_tilemap.set_cell(key_as_vector, source_id, str_to_var("Vector2i"+cell_data.atlas_coords))
	
	# load markers
	if map_data.has("markers"):
		for marker_name: String in map_data.markers.keys():
			var new_world_marker = world_marker_scene.instantiate() as WorldMarker
			new_world_marker.global_position = str_to_var("Vector2"+map_data.markers[marker_name].global_position) 
			markers.add_child(new_world_marker)
			new_world_marker.marker_description = map_data.markers[marker_name].marker_description
			new_world_marker.marker_color = str_to_var("Color"+map_data.markers[marker_name].marker_color) 
			new_world_marker.marker_name = map_data.markers[marker_name].marker_name
	
	last_map_loaded_path = map_path

func save_current_map(map_path: String, tileset_config_file: String) -> void:
	var map_data = {}
	
	map_data.world_map = {}
	map_data.decals_map = {}
	
	map_data.world_map.cells = {}
	map_data.decals_map.cells = {}
	
	# Create the .cells  key is cell_coord and value is dictionary
	for cell_coord: Vector2i in editor.world_tilemap.get_used_cells(): # loop for the used cells to create the cell data to save
		map_data.world_map.cells[cell_coord] = {
			"atlas_coords": editor.world_tilemap.get_cell_atlas_coords(cell_coord),
			"source_id": editor.world_tilemap.get_cell_source_id(cell_coord)
		}
	
	for cell_coord: Vector2i in editor.decals_tilemap.get_used_cells(): # loop for the used cells to create the cell data to save
		map_data.decals_map.cells[cell_coord] = {
			"atlas_coords": editor.decals_tilemap.get_cell_atlas_coords(cell_coord),
			"source_id": editor.decals_tilemap.get_cell_source_id(cell_coord)
		}
	
	map_data.map_name = map_name_input.text
	map_data.tileset_resource_path = editor.world_tilemap.tile_set.resource_path
	
	map_data.markers = _get_markers_to_save()
	
	map_data.tileset_config_file = tileset_config_file
	
	SaveManager.save_map(map_path, map_file_dialog.current_file, map_data)


func export_tilemap_to_png(world_tilemap: TileMapLayer, output_path: String):
		# segurança
	var used_rect: Rect2i = world_tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		push_error("TileMap vazio — nada para exportar.")
		return

	# --- calcula tamanho em pixels do bounding box usando cell_size (apenas para estimativa de tamanho) ---
	var cell_size: Vector2 = world_tilemap.tile_set.tile_size
	var px_width := int(ceil(float(used_rect.size.x) * float(cell_size.x)))
	var px_height := int(ceil(float(used_rect.size.y) * float(cell_size.y)))

	# --- calcula o offset correto em pixels usando map_to_world (resolve hex/isometria/offsets) ---
	var pixel_origin: Vector2 = world_tilemap.map_to_local(used_rect.position)

	# --- cria SubViewport e container e garante que o container tenha o mesmo tamanho ---
	var sv := SubViewport.new()
	sv.size = Vector2i(px_width, px_height)
	sv.transparent_bg = true

	var svc := SubViewportContainer.new()
	# garante que o container reserve o espaço necessário (Control API)
	svc.size = Vector2(px_width, px_height)
	svc.custom_minimum_size = Vector2(px_width, px_height)
	svc.add_child(sv)

	# adiciona à cena para que o SubViewport renderize
	add_child(svc)

	# --- duplica o TileMap e posiciona usando o pixel_origin calculado ---
	var temp_tm := world_tilemap.duplicate()
	# força a referência ao tileset original (segurança)
	temp_tm.tile_set = world_tilemap.tile_set
	# posiciona a cópia de forma que a célula usada mais à esquerda/cima vá para 0,0 do viewport
	temp_tm.position = -pixel_origin
	sv.add_child(temp_tm)

	# espera frame para o SubViewport ter conteúdo renderizado
	await get_tree().process_frame

	# captura a textura/imagem
	var tex := sv.get_texture()
	if tex == null:
		push_error("SubViewport não retornou textura.")
		svc.queue_free()
		return

	var img: Image = tex.get_image()
	img.flip_y() # normalmente necessário
	var err := img.save_png(output_path)
	if err == OK:
		print("Exportado para:", output_path)
	else:
		push_error("Erro ao salvar PNG: " + str(err))

	# limpa
	svc.queue_free()


func _get_markers_to_save() -> Dictionary:
	var result := {}
	
	for child: WorldMarker in markers.get_children():
		if child is WorldMarker:
			var marker_data = {}
			marker_data.global_position = child.global_position
			marker_data.marker_name = child.marker_name
			marker_data.marker_color = child.marker_color
			marker_data.marker_description = child.marker_description
			result[child.name] = marker_data
	return result
