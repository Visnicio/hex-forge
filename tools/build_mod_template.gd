## Generates templates/mod_template: a tiny standalone Godot project with a complete example tileset mod
## (ground tiles with biome/is_water/blend_color custom data, road and river tiles on a terrain, an extra path style)
## and a "Mod PCK" export preset. Run from the HexForge project folder:[br]
## [code]godot --headless --path . --script res://tools/build_mod_template.gd[/code][br]
## The tile art is drawn here from the real hex geometry of the template TileSet (sides from get_neighbor_cell),
## so the road/river pieces always meet the sides their peering bits say
extends SceneTree

const TEMPLATE: String = "res://templates/mod_template"
const MOD: String = "my_tileset"
const TILE: int = 64

## The editor classes a mod's resources point to, copied so the template project opens without errors.
## They are excluded from the exported pck so a mod can never replace the game's own scripts
const DEFINITIONS: Array[String] = [
	"res://resources/definitions/tilesets/map_tileset_configuration.gd",
	"res://resources/definitions/modding/mod_info_resource.gd",
	"res://resources/definitions/paths/path_style.gd",
]

## atlas coords -> [biome, is_water, color]
const GROUND: Dictionary = {
	Vector2i(0, 0): ["grassland", false, Color(0.42, 0.66, 0.27)],
	Vector2i(1, 0): ["ocean", true, Color(0.16, 0.42, 0.75)],
	Vector2i(2, 0): ["desert", false, Color(0.86, 0.75, 0.45)],
	Vector2i(3, 0): ["forest", false, Color(0.16, 0.38, 0.17)],
}
## atlas coords -> sides (screen directions) the road leaves through
const ROADS: Dictionary = {
	Vector2i(0, 1): ["left", "right"],
	Vector2i(1, 1): ["top-left", "bottom-right"],
	Vector2i(2, 1): ["top-right", "bottom-left"],
	Vector2i(3, 1): ["right"],
	Vector2i(4, 1): ["left"],
}
const RIVERS: Dictionary = {
	Vector2i(0, 2): ["left", "right"],
	Vector2i(1, 2): ["top-left", "bottom-right"],
	Vector2i(2, 2): ["top-right", "bottom-left"],
}
const DIRECTIONS: Dictionary = {
	"right": Vector2(1, 0), "left": Vector2(-1, 0), "top-right": Vector2(1, -1), "top-left": Vector2(-1, -1),
	"bottom-right": Vector2(1, 1), "bottom-left": Vector2(-1, 1),
}
const SIDE_KEYS: Dictionary = {
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: "right_side", TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE: "bottom_right_side",
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE: "bottom_left_side", TileSet.CELL_NEIGHBOR_LEFT_SIDE: "left_side",
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE: "top_left_side", TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE: "top_right_side",
}


func _init() -> void:
	var root_dir: String = ProjectSettings.globalize_path(TEMPLATE)
	DirAccess.make_dir_recursive_absolute(root_dir.path_join(MOD))
	for definition: String in DEFINITIONS:
		var target: String = root_dir.path_join(definition.trim_prefix("res://"))
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(definition), target)

	# pointy-top hexes like most painted packs, the geometry comes from a real TileSet
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	tile_set.tile_size = Vector2i(TILE, TILE)
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = tile_set
	root.add_child(layer)
	var geometry: HexGeometry = HexGeometry.new(layer)
	var corners: PackedVector2Array = geometry.corner_offsets()
	var sides: Dictionary = _sides_by_direction(layer, tile_set) # direction -> [side, offset to the side middle]

	var image: Image = Image.create_empty(TILE * 5, TILE * 3, false, Image.FORMAT_RGBA8)
	for coords: Vector2i in GROUND.keys():
		_draw_hex(image, coords, corners, GROUND[coords][2])
	for coords: Vector2i in ROADS.keys():
		_draw_connections(image, coords, ROADS[coords], sides, Color(0.62, 0.48, 0.3), Color(0.3, 0.2, 0.1), 5.0)
	for coords: Vector2i in RIVERS.keys():
		_draw_connections(image, coords, RIVERS[coords], sides, Color(0.3, 0.6, 0.9), Color(0.1, 0.22, 0.38), 6.0)
	image.save_png(root_dir.path_join(MOD).path_join("tiles.png"))

	_write(root_dir.path_join(MOD).path_join("tileset.tres"), _tileset_text(sides))
	_write(root_dir.path_join(MOD).path_join("config.tres"), CONFIG_TEXT)
	_write(root_dir.path_join(MOD).path_join("mod_info.tres"), MOD_INFO_TEXT)
	_write(root_dir.path_join("project.godot"), PROJECT_TEXT)
	_write(root_dir.path_join("export_presets.cfg"), EXPORT_TEXT)
	print("template written to ", root_dir)
	quit()


func _sides_by_direction(layer: TileMapLayer, tile_set: TileSet) -> Dictionary:
	var result: Dictionary = {}
	var center: Vector2 = layer.map_to_local(Vector2i(4, 4))
	for side: int in TerrainMaskIndex.side_neighbors(tile_set):
		var offset: Vector2 = layer.map_to_local(layer.get_neighbor_cell(Vector2i(4, 4), side)) - center
		var best: String = ""
		var best_dot: float = -INF
		for direction: String in DIRECTIONS.keys():
			var dot: float = offset.normalized().dot((DIRECTIONS[direction] as Vector2).normalized())
			if dot > best_dot:
				best_dot = dot
				best = direction
		result[best] = [side, offset / 2.0] # half way to the neighbor center is the middle of the shared side
	return result


func _draw_hex(image: Image, coords: Vector2i, corners: PackedVector2Array, color: Color) -> void:
	var origin: Vector2 = Vector2(coords * TILE) + Vector2(TILE, TILE) / 2.0
	for y: int in TILE:
		for x: int in TILE:
			var point: Vector2 = Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(TILE, TILE) / 2.0
			if not Geometry2D.is_point_in_polygon(point, corners):
				continue
			var edge_distance: float = INF
			for i: int in corners.size():
				edge_distance = minf(edge_distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, corners[i], corners[(i + 1) % corners.size()])))
			# a little texture so the smoothing has something to work with
			var noise: float = (hash(Vector2i(x / 3, y / 3) + coords * 100) % 100) / 100.0 * 0.08 - 0.04
			var pixel: Color = color.darkened(0.35) if edge_distance < 1.5 else color.lightened(noise)
			image.set_pixelv(Vector2i(origin - Vector2(TILE, TILE) / 2.0) + Vector2i(x, y), pixel)


func _draw_connections(image: Image, coords: Vector2i, directions: Array, sides: Dictionary, fill: Color, outline: Color, width: float) -> void:
	var center: Vector2 = Vector2(TILE, TILE) / 2.0
	var ends: Array[Vector2] = []
	for direction: String in directions:
		ends.append(center + sides[direction][1])
	for pass_index: int in 2:
		var radius: float = width / 2.0 + (1.5 if pass_index == 0 else 0.0)
		var color: Color = outline if pass_index == 0 else fill
		for end: Vector2 in ends:
			for y: int in TILE:
				for x: int in TILE:
					var point: Vector2 = Vector2(x, y) + Vector2(0.5, 0.5)
					if point.distance_to(Geometry2D.get_closest_point_to_segment(point, center, end)) <= radius:
						image.set_pixelv(coords * TILE + Vector2i(x, y), color)


func _tileset_text(sides: Dictionary) -> String:
	var lines: PackedStringArray = []
	for coords: Vector2i in GROUND.keys():
		var data: Array = GROUND[coords]
		var color: Color = data[2]
		lines.append("%d:%d/0 = 0" % [coords.x, coords.y])
		lines.append("%d:%d/0/custom_data_0 = \"%s\"" % [coords.x, coords.y, data[0]])
		lines.append("%d:%d/0/custom_data_1 = %s" % [coords.x, coords.y, "true" if data[1] else "false"])
		lines.append("%d:%d/0/custom_data_2 = Color(%s, %s, %s, 1)" % [coords.x, coords.y, color.r, color.g, color.b])
	for terrain: int in 2:
		var pieces: Dictionary = ROADS if terrain == 0 else RIVERS
		for coords: Vector2i in pieces.keys():
			lines.append("%d:%d/0 = 0" % [coords.x, coords.y])
			lines.append("%d:%d/0/terrain_set = 0" % [coords.x, coords.y])
			lines.append("%d:%d/0/terrain = %d" % [coords.x, coords.y, terrain])
			for direction: String in pieces[coords]:
				lines.append("%d:%d/0/terrains_peering_bit/%s = %d" % [coords.x, coords.y, SIDE_KEYS[sides[direction][0]], terrain])
	return TILESET_TEXT % "\n".join(lines)


static func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


const TILESET_TEXT: String = """[gd_resource type="TileSet" format=3]

[ext_resource type="Texture2D" path="res://my_tileset/tiles.png" id="1_tiles"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_tiles"]
texture = ExtResource("1_tiles")
texture_region_size = Vector2i(64, 64)
%s

[resource]
resource_name = "My Tileset"
tile_shape = 3
tile_layout = 5
tile_size = Vector2i(64, 64)
terrain_set_0/mode = 2
terrain_set_0/terrain_0/name = "Road"
terrain_set_0/terrain_0/color = Color(0.62, 0.48, 0.3, 1)
terrain_set_0/terrain_1/name = "River"
terrain_set_0/terrain_1/color = Color(0.3, 0.6, 0.9, 1)
custom_data_layer_0/name = "biome"
custom_data_layer_0/type = 4
custom_data_layer_1/name = "is_water"
custom_data_layer_1/type = 1
custom_data_layer_2/name = "blend_color"
custom_data_layer_2/type = 20
sources/0 = SubResource("TileSetAtlasSource_tiles")
"""

const CONFIG_TEXT: String = """[gd_resource type="Resource" script_class="MapTilesetConfiguration" format=3]

[ext_resource type="Script" path="res://resources/definitions/tilesets/map_tileset_configuration.gd" id="1_config"]
[ext_resource type="TileSet" path="res://my_tileset/tileset.tres" id="2_tileset"]
[ext_resource type="Script" path="res://resources/definitions/paths/path_style.gd" id="3_style"]

[sub_resource type="Resource" id="Resource_cobblestone"]
script = ExtResource("3_style")
id = "my_tileset:cobblestone"
display_name = "Cobblestone"
kind = "road"
color = Color(0.6, 0.6, 0.62, 1)
width = 0.08
outline_color = Color(0.2, 0.2, 0.22, 1)
outline_width = 0.012
meander_amplitude = 0.04
meander_depth = 1
smoothing_iterations = 3

[resource]
script = ExtResource("1_config")
tileset_name = "My Tileset"
tileset_resource = ExtResource("2_tileset")
tilemap_scale = 1.0
auto_hex_art_offset = true
hex_art_offset = Vector2(0, 0)
road_terrain_set = 0
road_terrain = 0
river_terrain_set = 0
river_terrain = 1
path_styles = Array[ExtResource("3_style")]([SubResource("Resource_cobblestone")])
"""

const MOD_INFO_TEXT: String = """[gd_resource type="Resource" script_class="ModInfoResource" format=3]

[ext_resource type="Script" path="res://resources/definitions/modding/mod_info_resource.gd" id="1_info"]
[ext_resource type="Resource" path="res://my_tileset/config.tres" id="2_config"]

[resource]
script = ExtResource("1_info")
author = "Your Name"
mod_name = "My Tileset"
mod_configuration = ExtResource("2_config")
"""

const PROJECT_TEXT: String = """; HexForge tileset mod template, see README.md

config_version=5

[application]

config/name="HexForge Mod Template"
config/features=PackedStringArray("4.7")

[rendering]

textures/canvas_textures/default_texture_filter=0
"""

const EXPORT_TEXT: String = """[preset.0]

name="Mod PCK"
platform="Linux"
runnable=false
dedicated_server=false
custom_features=""
export_filter="resources"
export_files=PackedStringArray("res://my_tileset/mod_info.tres")
include_filter="my_tileset/*"
exclude_filter="resources/definitions/*"
export_path="../my_tileset.pck"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

binary_format/embed_pck=false
binary_format/architecture="x86_64"
"""
