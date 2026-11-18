class_name MarkerData extends RefCounted


var global_position: Vector2
var marker_color: Color
var marker_description: String
var marker_name: String
var marker_scale: Vector2


static func to_dict(data: MarkerData) -> Dictionary:
	return {
		"global_position": data.global_position,
		"marker_color": data.marker_color,
		"marker_description": data.marker_description,
		"marker_name": data.marker_name,
		"marker_scale": data.marker_scale,
	}

static func from_dict(dict: Dictionary) -> MarkerData:
	var new: MarkerData = MarkerData.new()

	# marker_scale is not required since maps saved before it existed dont have it
	assert(dict.has_all(["global_position", "marker_color", "marker_description", "marker_name"]), "ERROR - given dictionary does not contains all keys needed")

	new.global_position = MapData.parse_json_value(dict.get("global_position"), "Vector2", Vector2.ZERO)
	new.marker_color = MapData.parse_json_value(dict.get("marker_color"), "Color", Color.WHITE)
	new.marker_description = dict.get("marker_description", "NO DESCRIPTION SAVED")
	new.marker_name = dict.get("marker_name", "NO NAME SAVED"+str(Time.get_time_dict_from_system().second))
	new.marker_scale = MapData.parse_json_value(dict.get("marker_scale"), "Vector2", WorldMarker.DEFAULT_MARKER_SCALE)

	return new
