class_name MapData extends RefCounted

## Key is layer name on editor and value is the layer data
var layers: Dictionary[StringName, LayerData] # LayerData is a Refcounted, it needs to be a dictionary to save correctly
## Example "Alpha 0.3"
var manifest_version: StringName
var map_name: String
## Tileset configuration that will be loaded to render the map (saved as its resource path)
var map_tileset_configuration: MapTilesetConfiguration
## Key is marker node name and value is MarkerData
var markers: Dictionary[StringName, MarkerData]

static func to_dict(data: MapData) -> Dictionary:

	var layers_as_dict: Dictionary = {}
	for layer_name in data.layers.keys():
		layers_as_dict[layer_name] = LayerData.to_dict(data.layers[layer_name])

	var markers_as_dict: Dictionary = {}
	for marker_name in data.markers.keys():
		markers_as_dict[marker_name] = MarkerData.to_dict(data.markers[marker_name])

	var tileset_config_path: String = ""
	if data.map_tileset_configuration:
		tileset_config_path = data.map_tileset_configuration.resource_path

	return {
		"layers": layers_as_dict,
		"manifest_version": data.manifest_version,
		"map_tileset_configuration": tileset_config_path,
		"map_name": data.map_name,
		"markers": markers_as_dict
	}

## Parses the raw dictionary read from the save json into a [code]MapData[/code]
static func from_dict(dict: Dictionary) -> MapData:
	var new: MapData = MapData.new()

	new.map_name = dict.get("map_name", "No Name Saved")
	new.manifest_version = dict.get("manifest_version", "")

	var tileset_config_path: String = str(dict.get("map_tileset_configuration", ""))
	if ResourceLoader.exists(tileset_config_path):
		new.map_tileset_configuration = load(tileset_config_path) as MapTilesetConfiguration
	else:
		push_error("Tileset configuration not found at: '%s'" % tileset_config_path)

	var raw_layers: Dictionary = dict.get("layers", {})
	for layer_name: String in raw_layers.keys():
		new.layers[layer_name] = LayerData.from_dict(raw_layers[layer_name])

	var raw_markers: Dictionary = dict.get("markers", {})
	for marker_key: String in raw_markers.keys():
		new.markers[marker_key] = MarkerData.from_dict(raw_markers[marker_key])

	return new

## JSON turns built-in types (Vector2, Vector2i, Color...) into strings like "(1.0, 2.0)"[br]
## this converts them back using the type name as prefix, e.g. [code]parse_json_value("(1, 2)", "Vector2i", Vector2i.ZERO)[/code]
static func parse_json_value(value: Variant, type_name: String, fallback: Variant) -> Variant:
	if value == null:
		return fallback
	if value is String:
		var parsed: Variant = str_to_var(type_name + value)
		return fallback if parsed == null else parsed
	return value
