## Data layout/save file of a map, contains relevant data to store and load from a map
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
## Key is hex position in tile coords, value is the hex data
var hexes_data: Dictionary[Vector2i, HexData] = {}
## Roads and rivers, key is the path id
var paths: Dictionary[String, PathData] = {}
## Seed of the meander of every path, each segment mixes it with its own key so editing one segment doesnt move the rest
var path_seed: int = 0
## Name of the user layer the paths are drawn right above, empty means the bottom layer
var path_anchor_layer: String = ""
## Map wide default of [member PathData.render_mode]
var path_render_mode: String = "auto"
## Format of the file this was loaded from, see [MapMigrations]
var format_version: int = MapMigrations.CURRENT_FORMAT_VERSION

static func to_dict(data: MapData) -> Dictionary:

	var layers_as_dict: Dictionary = {}
	for layer_name in data.layers.keys():
		layers_as_dict[layer_name] = LayerData.to_dict(data.layers[layer_name])

	var markers_as_dict: Dictionary = {}
	for marker_name in data.markers.keys():
		markers_as_dict[marker_name] = MarkerData.to_dict(data.markers[marker_name])

	var hexes_as_dict: Dictionary = {}
	for tile_coord: Vector2i in data.hexes_data.keys():
		hexes_as_dict[tile_coord] = HexData.to_dict(data.hexes_data[tile_coord])

	var paths_as_dict: Dictionary = {}
	for path_id: String in data.paths.keys():
		paths_as_dict[path_id] = PathData.to_dict(data.paths[path_id])

	var tileset_config_path: String = ""
	if data.map_tileset_configuration:
		tileset_config_path = data.map_tileset_configuration.resource_path

	return {
		"layers": layers_as_dict,
		"manifest_version": data.manifest_version,
		"map_tileset_configuration": tileset_config_path,
		"map_name": data.map_name,
		"markers": markers_as_dict,
		"hexes_data": hexes_as_dict,
		"format_version": MapMigrations.CURRENT_FORMAT_VERSION,
		"paths": paths_as_dict,
		"path_settings": {
			"seed": data.path_seed,
			"anchor_layer": data.path_anchor_layer,
			"render_mode": data.path_render_mode,
		},
	}

## Parses the raw dictionary read from the save json into a [code]MapData[/code]
static func from_dict(raw_dict: Dictionary) -> MapData:
	var new: MapData = MapData.new()
	new.format_version = MapMigrations.get_format_version(raw_dict)
	# older saves are upgraded first, so everything below only deals with the current format
	var dict: Dictionary = MapMigrations.migrate(raw_dict)

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

	# maps saved before hex data existed dont have this key, so it defaults to empty
	var raw_hexes: Dictionary = dict.get("hexes_data", {})
	for raw_coord: String in raw_hexes.keys():
		var hex_data: HexData = HexData.from_dict(raw_hexes[raw_coord])
		new.hexes_data[hex_data.tile_coord] = hex_data

	var raw_paths: Dictionary = dict.get("paths", {})
	for raw_path: Variant in raw_paths.values():
		if not raw_path is Dictionary:
			continue
		var path_data: PathData = PathData.from_dict(raw_path)
		if path_data != null:
			new.paths[path_data.id] = path_data

	var path_settings: Dictionary = dict.get("path_settings", {})
	# maps without a seed get one now, they had no paths so nothing changes on screen
	new.path_seed = int(path_settings.get("seed", randi()))
	new.path_anchor_layer = str(path_settings.get("anchor_layer", ""))
	new.path_render_mode = str(path_settings.get("render_mode", "auto"))

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
