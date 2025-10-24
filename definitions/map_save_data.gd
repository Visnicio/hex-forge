## This is basically a internal type/struct, can be used for better autocomplete
class_name MapSaveData
extends RefCounted

var map_name: String
var tileset_resource_path: String
var cells: Dictionary[Vector2i, CellSaveData]

func to_dict() -> Dictionary:
	
	var cells_dict: Dictionary = {}
	for key in cells.keys():
		cells_dict[key] = cells[key].to_dict()
	
	return {
		"map_name": map_name,
		"tileset_resource_path": tileset_resource_path,
		"cells": cells_dict
	}
