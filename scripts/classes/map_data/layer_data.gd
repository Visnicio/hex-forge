## Class responsible for holding data of a certain layer in the map save json
class_name LayerData extends RefCounted

## which cells are occupied, key is the position on the tilemap[br]
## value is a Dictionary which contains [code]atlas_coords[/code][br]
## and [code]source_id[/code] to sample from the tileset
var cells: Dictionary[Vector2i, Dictionary]
## Display order
var index: int

static func to_dict(data: LayerData) -> Dictionary:
	return {
		"cells": data.cells,
		"index": data.index
	}

static func from_dict(dict: Dictionary) -> LayerData:
	var new: LayerData = LayerData.new()
	
	assert(dict.has_all(["cells", "index"]), "ERROR - given dictionary does not contains all keys needed")
	
	new.index = int(dict.get("index", 0))
	
	# json keys and vectors come as strings, and numbers as floats
	var raw_cells: Dictionary = dict.get("cells", {})
	for raw_coord: String in raw_cells.keys():
		var cell_coord: Vector2i = MapData.parse_json_value(raw_coord, "Vector2i", Vector2i.ZERO)
		var raw_cell: Dictionary = raw_cells[raw_coord]
		new.cells[cell_coord] = {
			"atlas_coords": MapData.parse_json_value(raw_cell.get("atlas_coords"), "Vector2i", Vector2i.ZERO),
			"source_id": int(raw_cell.get("source_id", 0)),
		}
	
	return new
