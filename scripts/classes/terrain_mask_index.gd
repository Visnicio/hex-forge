## Index of the path tiles a mod declares through a TileSet terrain: "which tile connects exactly these sides".[br]
## The modder sets up road/river tiles the normal Godot way (a terrain set, a terrain, peering bits on the sides
## the road leaves the hex through). Instead of letting [method TileMapLayer.set_cells_terrain_path] pick tiles
## (it rewrites neighbors on its own and silently picks "close enough" tiles), the editor computes the exact set of
## sides each cell connects to and looks the tile up here, so a missing combination is detected exactly and can be
## drawn in vector or replaced by a tile picked by hand.[br]
## Sides are [enum TileSet.CellNeighbor] values valid for the tileset (6 on hexes), the actual neighbor cell of a side
## comes from [method TileMapLayer.get_neighbor_cell], so there is no hex math here either
class_name TerrainMaskIndex extends RefCounted

var tile_set: TileSet
var terrain_set: int
var terrain: int
## Side [enum TileSet.CellNeighbor]s of this tileset, bit i of a mask is sides[i]
var sides: Array[int] = []

## mask -> Array of {source_id, atlas_coords, alternative}
var _by_mask: Dictionary[int, Array] = {}
var _entries: Array[Dictionary] = []


## Returns null when the tileset doesnt have that terrain or it cant describe sides (e.g. a corners only terrain set)
static func build(from_tile_set: TileSet, from_terrain_set: int, from_terrain: int) -> TerrainMaskIndex:
	if from_tile_set == null or from_terrain_set < 0 or from_terrain < 0:
		return null
	if from_terrain_set >= from_tile_set.get_terrain_sets_count():
		push_warning("TerrainMaskIndex - terrain set %d doesnt exist in the tileset, falling back to vector" % from_terrain_set)
		return null
	if from_terrain >= from_tile_set.get_terrains_count(from_terrain_set):
		push_warning("TerrainMaskIndex - terrain %d doesnt exist in terrain set %d, falling back to vector" % [from_terrain, from_terrain_set])
		return null

	var index: TerrainMaskIndex = TerrainMaskIndex.new()
	index.tile_set = from_tile_set
	index.terrain_set = from_terrain_set
	index.terrain = from_terrain
	if from_tile_set.get_terrain_set_mode(from_terrain_set) != TileSet.TERRAIN_MODE_MATCH_CORNERS:
		index.sides = side_neighbors(from_tile_set)
	if index.sides.is_empty():
		push_warning("TerrainMaskIndex - terrain set %d has no side peering bits (use 'Match Sides' or 'Match Corners and Sides')" % from_terrain_set)
		return null
	index._scan()
	return index


## The side neighbors that exist for this tile shape and orientation (6 on hexes), as documented for terrain peering bits.[br]
## Which side is which on screen comes from [method TileMapLayer.get_neighbor_cell], never from hex math here
static func side_neighbors(from_tile_set: TileSet) -> Array[int]:
	match from_tile_set.tile_shape:
		TileSet.TILE_SHAPE_SQUARE:
			return [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
		TileSet.TILE_SHAPE_ISOMETRIC:
			return [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	# hexagon and half offset square
	if from_tile_set.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		return [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	return [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]


func _scan() -> void:
	for source_index: int in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(source_index)
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index: int in source.get_tiles_count():
			var atlas_coords: Vector2i = source.get_tile_id(tile_index)
			for alternative_index: int in source.get_alternative_tiles_count(atlas_coords):
				var alternative: int = source.get_alternative_tile_id(atlas_coords, alternative_index)
				var data: TileData = source.get_tile_data(atlas_coords, alternative)
				if data.terrain_set != terrain_set or data.terrain != terrain:
					continue
				var mask: int = 0
				for i: int in sides.size():
					if data.get_terrain_peering_bit(sides[i]) == terrain:
						mask |= 1 << i
				var entry: Dictionary = {"source_id": source_id, "atlas_coords": atlas_coords, "alternative": alternative, "mask": mask}
				_entries.append(entry)
				if not _by_mask.has(mask):
					_by_mask[mask] = []
				_by_mask[mask].append(entry)


## Mask of the sides of [param cell] that lead to one of the [param connected] cells
func mask_for(layer: TileMapLayer, cell: Vector2i, connected: Dictionary) -> int:
	var mask: int = 0
	for i: int in sides.size():
		if connected.has(layer.get_neighbor_cell(cell, sides[i])):
			mask |= 1 << i
	return mask


## First tile that connects exactly these sides, or an empty dictionary
func find(mask: int) -> Dictionary:
	var found: Array = _by_mask.get(mask, [])
	return found[0] if not found.is_empty() else {}


func has_mask(mask: int) -> bool:
	return _by_mask.has(mask)


## Every tile of the terrain (for picking one by hand)
func entries() -> Array[Dictionary]:
	return _entries


## How many of the possible side combinations (at least 1 side) have a tile
func coverage() -> Vector2i:
	var covered: int = 0
	for mask: int in _by_mask.keys():
		if mask != 0:
			covered += 1
	return Vector2i(covered, (1 << sides.size()) - 1)


## Human readable sides of a mask, e.g. "top-left + bottom-right"
func describe(mask: int) -> String:
	var names: PackedStringArray = []
	for i: int in sides.size():
		if mask & (1 << i):
			names.append(side_name(sides[i]))
	return " + ".join(names) if not names.is_empty() else "no sides"


static func side_name(neighbor: int) -> String:
	match neighbor:
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE: return "right"
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE: return "bottom-right"
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: return "bottom"
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE: return "bottom-left"
		TileSet.CELL_NEIGHBOR_LEFT_SIDE: return "left"
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE: return "top-left"
		TileSet.CELL_NEIGHBOR_TOP_SIDE: return "top"
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE: return "top-right"
	return "?"
