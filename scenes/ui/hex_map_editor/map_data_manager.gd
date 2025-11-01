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

var editor: HexMapEditor
var current_state: State = State.LOADING
var last_map_loaded_path: String = ""

func _ready() -> void:
	editor = get_parent() as HexMapEditor
	
	map_file_dialog.add_filter("*.json", "Map Files")
	
	export_map_button.pressed.connect(func():
		export_tilemap_to_png(editor.world_tilemap, "res://test.png")
		)
	
	new_map_button.pressed.connect(func():
		editor.clear_maps()
		for child in editor.tiles_grid_container.get_children():
			child.queue_free()
		)
	
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

	
func on_file_selected(map_path: String) -> void:
	if current_state == State.SAVING:
		save_current_map(map_path)
		
	elif current_state == State.LOADING:
		load_map_into_editor(map_path);


func load_map_into_editor(map_path: String) -> void:
	editor.clear_maps()
	for child in editor.tiles_grid_container.get_children():
		child.queue_free()
	
	var map_data: Dictionary = SaveManager.load_map(map_path)
	map_name_input.text = map_data.get("map_name", "No Name Saved")
	editor.load_tileset_for_map(map_data.get("tileset_resource_path"))
	
	# load world map
	for cell_data_key: String in map_data.world_map.cells.keys():
		var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
		var cell_data: Dictionary = map_data.world_map.cells[cell_data_key]
		editor.world_tilemap.set_cell(key_as_vector, 0, str_to_var("Vector2i"+cell_data.atlas_coords))
	
	# load decals map
	if !map_data.has("decals_map"): return
	for cell_data_key: String in map_data.decals_map.cells.keys():
		var key_as_vector: Vector2i = str_to_var("Vector2i"+cell_data_key) as Vector2i
		var cell_data: Dictionary = map_data.decals_map.cells[cell_data_key]
		editor.decals_tilemap.set_cell(key_as_vector, 0, str_to_var("Vector2i"+cell_data.atlas_coords))
		
	last_map_loaded_path = map_path

func save_current_map(map_path: String) -> void:
	var map_data = {}
	
	map_data.world_map = {}
	map_data.decals_map = {}
	
	map_data.world_map.cells = {}
	map_data.decals_map.cells = {}
	
	# Create the .cells  key is cell_coord and value is dictionary
	for cell_coord: Vector2i in editor.world_tilemap.get_used_cells(): # loop for the used cells to create the cell data to save
		map_data.world_map.cells[cell_coord] = {
			"atlas_coords": editor.world_tilemap.get_cell_atlas_coords(cell_coord)
		}
	
	for cell_coord: Vector2i in editor.decals_tilemap.get_used_cells(): # loop for the used cells to create the cell data to save
		map_data.decals_map.cells[cell_coord] = {
			"atlas_coords": editor.decals_tilemap.get_cell_atlas_coords(cell_coord)
		}
	
	map_data.map_name = map_name_input.text
	map_data.tileset_resource_path = editor.world_tilemap.tile_set.resource_path
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
