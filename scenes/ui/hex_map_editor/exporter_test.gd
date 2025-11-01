@tool
extends Node

@export_tool_button("Generate") var generate_button = generate_viewport
@export_tool_button("Delete") var delete_stuff = clear_viewport

@export var world_tilemap: TileMapLayer
@export var test_viewport: SubViewport
@export var export_viewport_container: SubViewportContainer


func _ready() -> void:
	print("teste")


func generate_viewport() -> void:
	print("generating viewport")
	
	var used_rect = world_tilemap.get_used_rect()
	var cell_size = world_tilemap.tile_set.tile_size
	
	var width = int(used_rect.size.x * cell_size.x)
	var height = int(used_rect.size.y * cell_size.y)
	print_debug(width, " ", height)
	test_viewport.size = Vector2(width, height)
	export_viewport_container.size = Vector2(width, height)
	
	# Cria uma cópia do TileMap para renderizar
	var temp_tilemap = world_tilemap.duplicate()
	# Reposiciona o TileMap para começar em (0,0)
	temp_tilemap.position = -used_rect.position * cell_size
	print_debug(temp_tilemap.position)
	test_viewport.add_child(temp_tilemap)
	
	await get_tree().create_timer(1).timeout # Espera um frame pra renderizar
	
	# Captura a imagem
	#var image: Image = test_viewport.get_texture().get_image()
	#image.save_png(output_path)
	

func clear_viewport() -> void:
	print("cleaning viewport")
	for child in test_viewport.get_children():
		child.queue_free()
	
