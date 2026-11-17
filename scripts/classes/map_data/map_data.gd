class_name MapData extends RefCounted

## Key is layer name on editor and value is the layer data
var layers: Dictionary[StringName, LayerData] # LayerData is a Refcounted, it needs to be a dictionary to save correctly
## Example "Alpha 0.3"
var manifest_version: StringName
var map_name: String
## Tileset that will be loaded to render the map
var map_tileset_configuration: TileSet
## Key is marker display name and value is MarkerData
var markers: Dictionary[StringName, MarkerData]

static func to_dict(data: MapData) -> Dictionary:
	
	var layers_as_dict: Dictionary = {}
	for layer_name in data.layers.keys():
		layers_as_dict[layer_name] = LayerData.to_dict(data.layers[layer_name])

	var markers_as_dict: Dictionary = {}
	for marker_name in data.markers.keys():
		markers_as_dict[marker_name] = MarkerData.to_dict(data.markers[marker_name])
	
	return {
		"layers": layers_as_dict,
		"manifest_version": data.manifest_version,
		"map_tileset_configuration": data.map_tileset_configuration,
		"map_name": data.map_name,
		"markers": markers_as_dict
	}
	
