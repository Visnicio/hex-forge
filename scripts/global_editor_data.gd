## A autload used to store global variables to avoid Dependecy INjenction hell
extends Node

var map_editor_ref: HexMapEditor
var layers_tilemaps_holder: Node2D
var user_layers: UserLayers


# generally we should avoid putting logic here to keep the app event driven and light on the CPU side
# but sometimes things needs to be constantly checked, so go wild
func _physics_process(delta: float) -> void:
	_sync_tileset_data_between_layers()


func _sync_tileset_data_between_layers() -> void:
	if map_editor_ref == null: return
	if map_editor_ref.current_tileset == null: return
	if user_layers == null: return
	
	for layer: UserLayer in user_layers.get_all_layers():
		layer.layer_tilemap_ref.tile_set = map_editor_ref.current_tileset
		# bad practice again, it makes the code dependent on the pencil tilemap but it is what it is
		# TODO - HexMapEditor._update_tilesets_scales could be a solution but its 2am and im tired
		layer.layer_tilemap_ref.scale = map_editor_ref.pencil_tilemap.scale
	
