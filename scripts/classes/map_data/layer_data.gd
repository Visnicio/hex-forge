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
