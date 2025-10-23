extends Node2D

@export var tileset_picker_button: Button
@export var tileset_picker: FileDialog
@export var tiles_grid_container: GridContainer

@export_category("Tilemaps")
@export var world_tilemap: TileMapLayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tileset_picker_button.pressed.connect(_on_tileset_picker_button_pressed)
	tileset_picker.file_selected.connect(_on_tileset_selected)
	
	# clear defaults
	world_tilemap.clear()
	world_tilemap.tile_set = null


func _on_tileset_picker_button_pressed() -> void:
	tileset_picker.show()


func _on_tileset_selected(selected_file_path: String) -> void:
	# load the tileset
	var loaded_tileset: TileSet = load(selected_file_path)
	
	#get its source
	var tileset_source: TileSetSource = loaded_tileset.get_source(0)
	
	var rows: int = tileset_source.get_atlas_grid_size().y
	# but it is 1-indexed, so I need to subtract -1 to query i coords
	var cols: int = tileset_source.get_atlas_grid_size().x
	
	if tileset_source is TileSetAtlasSource: # if selected is a source
		for row in rows:
			for col in cols:
				# for each tile in tileset, check if its set to usable
				if !tileset_source.has_tile(Vector2i(col, row)): continue
				
				# creates a new atlas to hold the tile texture
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = tileset_source.texture
				atlas.region = tileset_source.get_tile_texture_region(Vector2i(col, row))
				
				# creates the button
				var texture_r: TextureRect = TextureRect.new()
				texture_r.texture = atlas
				tiles_grid_container.add_child(texture_r)
