## Custom data the user wrote for a specific hex, independent of markers and layers
class_name HexData extends RefCounted

## Color of the badge drawn on the hex, used when the user never picked one
const DEFAULT_COLOR: Color = Color(1.0, 0.78, 0.25)

var tile_coord: Vector2i
var hex_name: String = ""
var hex_freetext: String = ""
## Color of the badge drawn on the hex (HexDataIndicators), can be used to group hexes, e.g. a political map
var hex_color: Color = DEFAULT_COLOR


## True when the user never wrote anything in it, so it doesnt need to be saved
func is_empty() -> bool:
	# a hex with only a color picked still counts, so the user can paint regions without naming every hex
	# (approx because the color goes through JSON and can come back with a tiny difference)
	return hex_name.strip_edges().is_empty() and hex_freetext.strip_edges().is_empty() \
		and hex_color.is_equal_approx(DEFAULT_COLOR)


static func to_dict(data: HexData) -> Dictionary:
	return {
		"tile_coord": data.tile_coord,
		"hex_name": data.hex_name,
		"hex_freetext": data.hex_freetext,
		"hex_color": data.hex_color
	}

static func from_dict(dict: Dictionary) -> HexData:
	var new: HexData = HexData.new()

	# only tile_coord is required, so adding new fields later doesnt break older saves
	assert(dict.has("tile_coord"), "ERROR - given dictionary does not contains all keys needed")

	# JSON turns Vector2i into a string like "(1, 2)", so it needs to be parsed back
	new.tile_coord = MapData.parse_json_value(dict.get("tile_coord"), "Vector2i", Vector2i.ZERO)
	new.hex_name = dict.get("hex_name", "")
	new.hex_freetext = dict.get("hex_freetext", "")
	new.hex_color = MapData.parse_json_value(dict.get("hex_color"), "Color", DEFAULT_COLOR)

	return new
