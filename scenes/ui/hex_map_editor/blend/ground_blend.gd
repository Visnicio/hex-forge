## Optional biome smoothing (and coastlines), purely visual: turning it on/off never touches the map data.[br]
## When on, the ground layers (the user layers at or below the paths anchor) are mirrored into a hidden viewport
## and rendered to a texture, a second hidden viewport renders an exact "distance to the hex border" mask
## ([EdgeMaskTileset]), and this node draws the ground texture back on screen through biome_blend.gdshader, which
## warps the reads with noise only near the hex borders. The original ground layers are hidden meanwhile.[br]
## In the ground viewport the mirrors keep only the hex body of tall tiles (the peaks are cut with the overhang shader),
## so the warp never wobbles mountain tops; the [OverhangPass] still draws the crisp peaks above roads/rivers.[br]
## Sits right before the [PathsLayer] in the tree with the same z, so it draws where the ground used to be
class_name GroundBlend extends Node2D

const BLEND_SHADER: Shader = preload("res://resources/shaders/biome_blend.gdshader")
const SETTINGS_SECTION: String = "biome_blend"

@export var reference_tilemap: TileMapLayer
@export var paths_layer: PathsLayer

## Smoothing on/off (a user preference, saved in [UserSettings], never in the map)
var enabled: bool = false:
	set(value):
		enabled = value
		if _loaded: # not while loading the saved value
			UserSettings.set_value(SETTINGS_SECTION, "enabled", value)
		_dirty = true
## 0..1
var intensity: float = 0.6:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		if _loaded: # not while loading the saved value
			UserSettings.set_value(SETTINGS_SECTION, "intensity", intensity)
## Off by default too, so maps look exactly as before until the user turns it on
var coastlines: bool = false:
	set(value):
		coastlines = value
		if _loaded: # not while loading the saved value
			UserSettings.set_value(SETTINGS_SECTION, "coastlines", value)
		if _coast:
			_coast.visible = value
			_coast.mark_dirty()

## False while _ready reads the saved preferences, so reading them doesnt write the file back
var _loaded: bool = false
var _ground_viewport: SubViewport
var _mask_viewport: SubViewport
var _ground_root: Node2D
var _mask_root: Node2D
var _coast: CoastlineOverlay
var _material: ShaderMaterial

var _mask_tile_set: TileSet
var _hex_only_materials: Dictionary[int, ShaderMaterial] = {}
var _hidden_layers: Array[TileMapLayer] = []
var _dirty: bool = true
var _tileset_key: String = ""
var _ground_signature: String = ""


func _ready() -> void:
	enabled = UserSettings.get_value(SETTINGS_SECTION, "enabled", false)
	intensity = UserSettings.get_value(SETTINGS_SECTION, "intensity", 0.6)
	coastlines = UserSettings.get_value(SETTINGS_SECTION, "coastlines", false)
	_loaded = true

	_ground_viewport = _make_viewport("GroundViewport")
	_mask_viewport = _make_viewport("EdgeMaskViewport")
	_ground_root = Node2D.new()
	_ground_viewport.add_child(_ground_root)
	_mask_root = Node2D.new()
	_mask_viewport.add_child(_mask_root)

	_material = ShaderMaterial.new()
	_material.shader = BLEND_SHADER
	_material.set_shader_parameter("ground_texture", _ground_viewport.get_texture())
	_material.set_shader_parameter("edge_mask", _mask_viewport.get_texture())
	material = _material

	_coast = CoastlineOverlay.new()
	_coast.name = "Coastlines"
	_coast.visible = coastlines
	add_child(_coast)

	SignalBus.map_cells_changed.connect(func() -> void:
		_dirty = true
		_coast.mark_dirty())


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.name = viewport_name
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func is_active() -> bool:
	return enabled and paths_layer.is_ready() and not paths_layer.ground_layers.is_empty()


func _process(_delta: float) -> void:
	z_index = paths_layer.z_index
	var geometry: HexGeometry = paths_layer.geometry

	var key: String = ""
	if paths_layer.is_ready():
		key = "%d|%s|%s" % [reference_tilemap.tile_set.get_instance_id(), geometry.art_offset, reference_tilemap.scale]
	if key != _tileset_key:
		_tileset_key = key
		_rebuild_tileset_resources(geometry)
		_dirty = true
		_coast.mark_dirty()
	if paths_layer.ground_signature != _ground_signature:
		_ground_signature = paths_layer.ground_signature
		_dirty = true
		_coast.mark_dirty()

	_coast.update(paths_layer.ground_layers, geometry, paths_layer.path_store.path_seed, reference_tilemap.global_transform)

	if not is_active():
		_restore_hidden_layers()
		_ground_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		return

	if _dirty:
		_dirty = false
		_rebuild_mirrors()
	_hide_ground_layers()
	_sync_viewports()
	queue_redraw()


func _draw() -> void:
	if not is_active():
		return
	draw_texture_rect(_ground_viewport.get_texture(), _screen_world_rect(), false)


## The part of the world currently on screen (this node sits at the origin of the world)
func _screen_world_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	return Rect2(inverse * Vector2.ZERO, inverse.basis_xform(screen_size))


func _sync_viewports() -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	for viewport: SubViewport in [_ground_viewport, _mask_viewport]:
		# same filtering as where the ground is normally drawn, or the untouched pixels would look different
		viewport.canvas_item_default_texture_filter = get_viewport().canvas_item_default_texture_filter
		viewport.canvas_item_default_texture_repeat = get_viewport().canvas_item_default_texture_repeat
		viewport.size = Vector2i(screen_size)
		viewport.canvas_transform = canvas
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# same chain of transforms as the real layers (parent, then the layer's own scale): with nearest filtering on
	# shrunk tiles, the tiniest float difference picks the neighbor texel and the "untouched" pixels would change
	var parent_transform: Transform2D = Transform2D.IDENTITY
	if not paths_layer.ground_layers.is_empty() and is_instance_valid(paths_layer.ground_layers[0]):
		parent_transform = (paths_layer.ground_layers[0].get_parent() as Node2D).global_transform
	for root: Node2D in [_ground_root, _mask_root]:
		root.transform = parent_transform

	var world: Rect2 = _screen_world_rect()
	_material.set_shader_parameter("strength", intensity)
	_material.set_shader_parameter("world_origin", world.position)
	_material.set_shader_parameter("world_per_pixel", world.size.x / maxf(screen_size.x, 1.0))
	_material.set_shader_parameter("screen_size", screen_size)
	_material.set_shader_parameter("hex_world_size", paths_layer.geometry.unit_size() * reference_tilemap.global_transform.get_scale().x)


func _rebuild_tileset_resources(geometry: HexGeometry) -> void:
	_mask_tile_set = null
	_hex_only_materials.clear()
	if geometry == null or not geometry.is_valid():
		return
	_mask_tile_set = EdgeMaskTileset.build(geometry)
	var tile_set: TileSet = geometry.layer.tile_set
	for source_index: int in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(source_index)
		var hex_only: ShaderMaterial = OverhangPass.make_material(tile_set.get_source(source_id) as TileSetAtlasSource, geometry, false)
		if hex_only != null:
			_hex_only_materials[source_id] = hex_only


func _rebuild_mirrors() -> void:
	for root: Node2D in [_ground_root, _mask_root]:
		for child: Node in root.get_children():
			child.queue_free()
	if _mask_tile_set == null:
		return

	var mask: TileMapLayer = TileMapLayer.new()
	mask.tile_set = _mask_tile_set
	mask.transform = reference_tilemap.transform
	_mask_root.add_child(mask)

	for ground: TileMapLayer in paths_layer.ground_layers:
		if not is_instance_valid(ground):
			continue
		# only tiles the OverhangPass redraws get their peaks cut here, cutting the others would leave holes
		var overhang: OverhangPass = paths_layer.overhang()
		var mirrors: Dictionary = {} # [source_id, is_tall] -> TileMapLayer
		for cell: Vector2i in ground.get_used_cells():
			var source_id: int = ground.get_cell_source_id(cell)
			var atlas_coords: Vector2i = ground.get_cell_atlas_coords(cell)
			var group: Array = [source_id, overhang.is_tall(source_id, atlas_coords)]
			if not mirrors.has(group):
				var mirror: TileMapLayer = TileMapLayer.new()
				mirror.tile_set = ground.tile_set
				mirror.material = _hex_only_materials.get(source_id, null) if group[1] else null
				mirror.transform = ground.transform
				_ground_root.add_child(mirror)
				mirrors[group] = mirror
			mirrors[group].set_cell(cell, source_id, atlas_coords, ground.get_cell_alternative_tile(cell))
			mask.set_cell(cell, 0, Vector2i.ZERO)


func _hide_ground_layers() -> void:
	for layer: TileMapLayer in _hidden_layers.duplicate():
		if not is_instance_valid(layer):
			_hidden_layers.erase(layer)
		elif not paths_layer.ground_layers.has(layer):
			layer.visible = true
			_hidden_layers.erase(layer)
	for layer: TileMapLayer in paths_layer.ground_layers:
		if is_instance_valid(layer) and layer.visible:
			layer.visible = false
			_hidden_layers.append(layer)


func _restore_hidden_layers() -> void:
	for layer: TileMapLayer in _hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_layers.clear()
