class_name UserLayers extends VBoxContainer

const USER_LAYER_SCENE = preload("uid://1ucpsbaewmj0")

## A node that will hold every tilemap for each layer
@export var tilemaps_holder: Node2D
## container that holds the layers
@export var layers_container: VBoxContainer

## Key is the layer, value is layer index (i thought it was better to have what changes (the layer index) on the value side 
## so we dont have to deal with rearranging the keys)
var all_user_layers: Dictionary[UserLayer, int] = {}
var last_indexed_layer: int = 0

func _ready() -> void:
	GlobalEditorData.user_layers = self
	# on startup we call this functions to simulate creating a new map, since at the time that the MapDataManager _ready function is
	# called, this node is not yet processed, thus creating a nullpointer
	delete_all_layers()
	add_base_layers()

## adds a new layer and creates a new tilemap for it
func add_new_layer(layer_name: String) -> void:
	var new_layer = USER_LAYER_SCENE.instantiate() as UserLayer
	new_layer.layer_name = layer_name
	
	var layer_tilemap: TileMapLayer = TileMapLayer.new()
	layer_tilemap.name = layer_name.replace(" ", "_") + "_TilemapLayer"
	
	# TODO - this is generally a bad practice, but I had problems with when addind a new layer, the selected tileset wouldnt replicate to 
	# the new tilemap layer, this needs to be changed.... eventually
	if GlobalEditorData.map_editor_ref != null and GlobalEditorData.map_editor_ref.current_tileset != null:
		layer_tilemap.tile_set = GlobalEditorData.map_editor_ref.current_tileset
	
	tilemaps_holder.add_child(layer_tilemap)
	
	new_layer.layer_tilemap_ref = layer_tilemap # the refcounted will keep track of this boy for us, wont lose reference out of scope
	layers_container.add_child(new_layer)
	all_user_layers[new_layer] = last_indexed_layer
	last_indexed_layer += 1 # adds one index for the next layer creation

func delete_all_layers() -> void:
	for layer: UserLayer in all_user_layers:
		layer.queue_free() # removes it from the scene tree (the checkbox and stuff)
	all_user_layers.clear()

## ads all base layers for a map (World and Decals)
func add_base_layers() -> void:
	add_new_layer("World")
	add_new_layer("Decals")

## Utility function so you dont have to type a for loop every time
func get_all_layers() -> Array[UserLayer]:
	var all : Array[UserLayer] =  []
	for layer in all_user_layers.keys():
		all.append(layer)
	return all

func _on_add_layer_button_pressed() -> void:
	add_new_layer("New Layer")
