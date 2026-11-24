## represents a general configuration of an usable tileset for the map editor, with a bunch of useful and needed stuff
class_name MapTilesetConfiguration extends Resource

## Used as a display for your tileset, will be shown on the Select Tileset dropdown
@export var tileset_name: String
## A referece to the tileset resource you created
@export var tileset_resource: TileSet:
	set(new_value):
		print("setting tileset resource")
		tileset_resource = new_value
		tileset_resource_path = tileset_resource.resource_path
## Holds a quick reference to the tileset the modder set, this is needed to exchange its resource location between targets
var tileset_resource_path: String 

## how much the tiles will eb scaled upon drawing
@export var tilemap_scale: float = 1

@export_group("Hex art alignment (optional)")
## When on, the editor guesses where the hex art is inside your tiles (assumes tiles taller than the hex
## have the hex at the bottom of the texture region). Turn it off and set [member hex_art_offset] if
## roads/rivers look shifted from your hexes
@export var auto_hex_art_offset: bool = true
## Offset in tile pixels from the logical cell center to the center of the hex art, only used when
## [member auto_hex_art_offset] is off
@export var hex_art_offset: Vector2 = Vector2.ZERO

@export_group("Roads and rivers (optional)")
## Terrain set of your TileSet holding road tiles (peering bits on the sides each road tile connects).
## -1 = your mod has no road tiles, roads are drawn as vector lines
@export var road_terrain_set: int = -1
## Terrain (inside [member road_terrain_set]) painted on the road tiles
@export var road_terrain: int = -1
## Same as [member road_terrain_set] for rivers that go through the hex centers.
## Rivers along the hex edges are always drawn as vector lines
@export var river_terrain_set: int = -1
@export var river_terrain: int = -1
## Extra styles for the vector roads/rivers, listed next to the built-in ones (ids should be unique, e.g. "my_mod:cobblestone")
@export var path_styles: Array[PathStyle] = []


## True when the mod provides road tiles (this file is copied into mod projects, so it only depends on PathStyle)
func provides_road_tiles() -> bool:
	return road_terrain_set >= 0 and road_terrain >= 0


func provides_river_tiles() -> bool:
	return river_terrain_set >= 0 and river_terrain >= 0
