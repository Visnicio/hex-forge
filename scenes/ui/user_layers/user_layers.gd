class_name UserLayers extends VBoxContainer

const USER_LAYER_SCENE = preload("uid://1ucpsbaewmj0")

## A node that will hold every tilemap for each layer
@export var tilemaps_holder: Node2D
## container that holds the layers
@export var layers_container: VBoxContainer

## key is index to show and value is layer
var all_user_layers: Dictionary[int, UserLayer] = {}

func _ready() -> void:
	GlobalEditorData.user_layers = self
	# on startup we call this functions to simulate creating a new map, since at the time that the MapDataManager _ready function is
	# called, this node is not yet processed, thus creating a nullpointer
	delete_all_layers()
	add_base_layers()
	
	SignalBus.layer_reorder_requested.connect(_on_layer_reorder_requested)

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
	all_user_layers[all_user_layers.size()] = new_layer

func delete_all_layers() -> void:
	for layer: UserLayer in all_user_layers.values():
		layer.queue_free()
	
	all_user_layers.clear()
	
	for child in tilemaps_holder.get_children():
		child.queue_free()

## ads all base layers for a map (World and Decals)
func add_base_layers() -> void:
	add_new_layer("Decals")
	add_new_layer("World")
	_refresh_layer_visuals()

## Utility function so you dont have to type a for loop every time
func get_all_layers() -> Array[UserLayer]:
	var all : Array[UserLayer] =  []
	for layer in all_user_layers.values():
		all.append(layer)
	return all

func swap_layers(index_a: int, index_b: int) -> void:
	if not all_user_layers.has(index_a) or not all_user_layers.has(index_b):
		push_error("Invalid indices")
		return
	var temp_layer = all_user_layers[index_a]
	
	all_user_layers[index_a] = all_user_layers[index_b]
	all_user_layers[index_b] = temp_layer

## Returns -1 if not found
func get_user_layer_index(user_layer: UserLayer) -> int:
	for index in all_user_layers.keys():
		if all_user_layers[index] == user_layer:
			return index
	return -1

func _on_add_layer_button_pressed() -> void:
	add_new_layer("New Layer")


func _on_layer_reorder_requested(layer: UserLayer, direction: int) -> void:
	var current_index = -1
	for idx in all_user_layers:
		if all_user_layers[idx] == layer:
			current_index = idx
			break
	
	if current_index == -1: return

	var target_index = current_index + direction
	if target_index < 0 or target_index >= all_user_layers.size():
		return

	swap_layers(target_index, current_index)

	_refresh_layer_visuals()
	print("moved layers")

func _refresh_layer_visuals() -> void:
	var total_layers = all_user_layers.size()
	
	for i in range(total_layers):
		if not all_user_layers.has(i): continue 
		
		var u_layer = all_user_layers[i]
		
		u_layer.get_parent().move_child(u_layer, i)
		
		if is_instance_valid(u_layer.layer_tilemap_ref):
			u_layer.layer_tilemap_ref.z_index = total_layers - i
			
			tilemaps_holder.move_child(u_layer.layer_tilemap_ref, total_layers - 1 - i)
