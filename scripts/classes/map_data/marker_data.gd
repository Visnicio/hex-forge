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