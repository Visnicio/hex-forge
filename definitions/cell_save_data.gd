## This is basically a internal type/struct, can be used for better autocomplete
class_name CellSaveData
extends RefCounted

var atlas_coords: Vector2i
var source_id: int = 0


func to_dict() -> Dictionary:
	return {
		"atlas_coords": atlas_coords,
		"source_id": source_id
	}
