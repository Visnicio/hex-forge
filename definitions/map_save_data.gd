## This is basically a internal type/struct, can be used for better autocomplete
class_name MapSaveData
extends RefCounted

var map_name: String
var tileset_resource_path: String
var cells: Dictionary[Vector2i, CellSaveData]
