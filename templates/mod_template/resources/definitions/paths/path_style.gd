## How a road or river is drawn by the vector renderer.[br]
## Every size is a FRACTION OF THE HEX SIZE (smallest side of the tileset tile_size),
## so the same style looks the same on a 28px pixel art hex and on a 256px painted one
class_name PathStyle extends Resource

## Unique id saved in the map, e.g. "builtin:road" or "my_mod:cobblestone"
@export var id: String
@export var display_name: String
## Which tool lists this style, "any" shows on both
@export_enum("road", "river", "any") var kind: String = "any"

@export_group("Line")
@export var color: Color = Color(0.55, 0.42, 0.28)
## Width relative to the hex size
@export_range(0.005, 0.5, 0.005) var width: float = 0.06
## Width multiplier at the first point (rivers: the source)
@export_range(0.05, 4.0, 0.05) var width_start_multiplier: float = 1.0
## Width multiplier at the last point (rivers: the mouth)
@export_range(0.05, 4.0, 0.05) var width_end_multiplier: float = 1.0
@export var outline_color: Color = Color(0.16, 0.11, 0.07)
## Outline thickness on each side, relative to the hex size (0 = no outline)
@export_range(0.0, 0.1, 0.001) var outline_width: float = 0.012
## Optional texture repeated along the line instead of the flat color
@export var texture: Texture2D

@export_group("Dashes")
## Dash length relative to the hex size, 0 = solid line
@export_range(0.0, 1.0, 0.005) var dash_length: float = 0.0
@export_range(0.0, 1.0, 0.005) var gap_length: float = 0.0

@export_group("Shape")
## How far the line wanders from the straight segment, relative to the segment length
@export_range(0.0, 0.5, 0.01) var meander_amplitude: float = 0.1
## Times each segment is split before smoothing (more = more wiggles)
@export_range(0, 5) var meander_depth: int = 2
## Chaikin smoothing passes
@export_range(0, 5) var smoothing_iterations: int = 2

@export_group("Bridge")
## Drawn where a road crosses a river, a simple wooden bridge is drawn when empty
@export var bridge_texture: Texture2D
@export var bridge_color: Color = Color(0.45, 0.3, 0.17)
