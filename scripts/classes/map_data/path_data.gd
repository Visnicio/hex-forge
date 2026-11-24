## A road or river drawn on the map, independent of the tileset that renders it.[br]
## Points are stored in tile coords only (never pixels or atlas coords), so the path survives a tileset swap:[br]
## - [code]Anchor.CELL[/code]: each point is a cell ([Vector2i]), the path goes center to center (roads)[br]
## - [code]Anchor.VERTEX[/code]: each point is a hex corner, stored as the sorted trio of the 3 cells
##   that meet there (see [method HexGeometry.make_vertex]), the path runs along the hex edges (rivers)
class_name PathData extends RefCounted

enum Kind { ROAD, RIVER }
enum Anchor { CELL, VERTEX }

const KIND_NAMES: PackedStringArray = ["road", "river"]
const ANCHOR_NAMES: PackedStringArray = ["cell", "vertex"]
## "auto" picks tiles when the mod provides them (phase 2), otherwise vector
const RENDER_MODES: PackedStringArray = ["auto", "vector", "tile"]

var id: String
var path_name: String = ""
var description: String = ""
var kind: Kind = Kind.ROAD
var anchor: Anchor = Anchor.CELL
## [code]Array[Vector2i][/code] for CELL paths, [code]Array[Array][/code] (vertex trios) for VERTEX paths.
## For rivers the first point is the source and the last one is the mouth
var points: Array = []
## Id of a [PathStyle], unknown ids fall back to the default style of the kind
var style_id: String = ""
var render_mode: String = "auto"
## Phase 2: per cell tile picked by hand when the mod has no tile for that connection
var tile_exceptions: Dictionary = {}


static func new_id() -> String:
	return "p_%08x%04x" % [randi(), randi() & 0xffff]


static func create(new_kind: Kind, new_anchor: Anchor) -> PathData:
	var data: PathData = PathData.new()
	data.id = new_id()
	data.kind = new_kind
	data.anchor = new_anchor
	data.style_id = PathStyles.default_style_id(new_kind)
	data.path_name = "New River" if new_kind == Kind.RIVER else "New Road"
	return data


## Deep copy, used for undo snapshots so editing the live path never changes a snapshot
func duplicate_data() -> PathData:
	var copy: PathData = PathData.new()
	copy.id = id
	copy.path_name = path_name
	copy.description = description
	copy.kind = kind
	copy.anchor = anchor
	copy.points = points.duplicate(true)
	copy.style_id = style_id
	copy.render_mode = render_mode
	copy.tile_exceptions = tile_exceptions.duplicate(true)
	return copy


## Compares only what is drawn and saved, used to skip undo actions that changed nothing
func same_as(other: PathData) -> bool:
	if other == null:
		return false
	return to_dict(self) == to_dict(other)


## Stable string key of a point, used to seed the meander and to compare points
func point_key(index: int) -> String:
	return PathData.key_of(points[index], anchor)


static func key_of(point: Variant, point_anchor: Anchor) -> String:
	if point_anchor == Anchor.CELL:
		return str(point)
	return HexGeometry.vertex_to_string(point)


static func to_dict(data: PathData) -> Dictionary:
	var raw_points: Array = []
	for point: Variant in data.points:
		raw_points.append(PathData.key_of(point, data.anchor))

	return {
		"id": data.id,
		"name": data.path_name,
		"description": data.description,
		"kind": KIND_NAMES[data.kind],
		"anchor": ANCHOR_NAMES[data.anchor],
		"points": raw_points,
		"style_id": data.style_id,
		"render_mode": data.render_mode,
		"tile_exceptions": data.tile_exceptions,
	}


## Returns [code]null[/code] when the entry is unusable, so one broken path doesnt stop the map from loading
static func from_dict(dict: Dictionary) -> PathData:
	var data: PathData = PathData.new()
	data.id = str(dict.get("id", ""))
	if data.id.is_empty():
		data.id = new_id()

	data.kind = maxi(KIND_NAMES.find(str(dict.get("kind", "road"))), 0) as Kind
	var anchor_index: int = ANCHOR_NAMES.find(str(dict.get("anchor", "")))
	if anchor_index == -1: # rivers default to edges, roads to centers
		anchor_index = Anchor.VERTEX if data.kind == Kind.RIVER else Anchor.CELL
	data.anchor = anchor_index as Anchor

	data.path_name = str(dict.get("name", ""))
	data.description = str(dict.get("description", ""))
	data.style_id = str(dict.get("style_id", PathStyles.default_style_id(data.kind)))
	data.render_mode = str(dict.get("render_mode", "auto"))
	if not RENDER_MODES.has(data.render_mode):
		data.render_mode = "auto"
	var raw_exceptions: Variant = dict.get("tile_exceptions", {})
	data.tile_exceptions = raw_exceptions if raw_exceptions is Dictionary else {}

	var raw_points: Variant = dict.get("points", [])
	if not raw_points is Array:
		push_warning("PathData - path '%s' has no valid points, skipping" % data.id)
		return null

	for raw_point: Variant in raw_points:
		var point: Variant = _parse_point(str(raw_point), data.anchor)
		if point == null:
			push_warning("PathData - skipping invalid point '%s' on path '%s'" % [raw_point, data.id])
			continue
		data.points.append(point)

	return data


static func _parse_point(raw: String, point_anchor: Anchor) -> Variant:
	if point_anchor == Anchor.CELL:
		var cell: Variant = str_to_var("Vector2i" + raw)
		return cell if cell is Vector2i else null
	return HexGeometry.vertex_from_string(raw)
