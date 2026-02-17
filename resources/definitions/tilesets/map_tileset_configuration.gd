class_name MapTilesetConfiguration extends Resource

## Used as a display for your tileset, will be shown on the Select Tileset dropdown
@export var tileset_name: String
## A referece to the tileset resource you created
@export var tileset_resource: TileSet
## how much the tiles will eb scaled upon drawing
@export var tilemap_scale: float = 1
