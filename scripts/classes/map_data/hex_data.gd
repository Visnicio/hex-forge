## Custom data the user wrote for a specific hex, independent of markers and layers
class_name HexData extends RefCounted

var tile_coord: Vector2i
var hex_name: String = ""
var hex_freetext: String = ""


## True when the user never wrote anything in it, so it doesnt need to be saved
func is_empty() -> bool:
	return hex_name.strip_edges().is_empty() and hex_freetext.strip_edges().is_empty()


static func to_dict(data: HexData) -> Dictionary:
	return {
		"tile_coord": data.tile_coord,
		"hex_name": data.hex_name,
		"hex_freetext": data.hex_freetext
	}

static func from_dict(dict: Dictionary) -> HexData:
	var new: HexData = HexData.new()

	# only tile_coord is required, so adding new fields later doesnt break older saves
	assert(dict.has("tile_coord"), "ERROR - given dictionary does not contains all keys needed")

	# JSON turns Vector2i into a string like "(1, 2)", so it needs to be parsed back
	new.tile_coord = MapData.parse_json_value(dict.get("tile_coord"), "Vector2i", Vector2i.ZERO)
	new.hex_name = dict.get("hex_name", "")
	new.hex_freetext = dict.get("hex_freetext", "")

	return new
