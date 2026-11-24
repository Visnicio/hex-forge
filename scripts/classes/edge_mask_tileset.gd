## Builds, at runtime, a "ghost" TileSet with the same shape, layout, orientation and tile_size as the mod's one,
## holding a single tile: a gradient that is 1 at the hex center and 0 on its border.[br]
## Painted on every ground cell in a hidden viewport it gives an exact "distance to the hex edge" mask for ANY
## layout, used by the biome smoothing shader to only touch pixels near the edges.[br]
## The hex shape comes from [method HexGeometry.corner_offsets] (no hex math), and the tile is shifted by the art
## offset so the mask lines up with the hex art, not the logical cell
class_name EdgeMaskTileset extends RefCounted


static func build(geometry: HexGeometry) -> TileSet:
	var source_set: TileSet = geometry.layer.tile_set
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_shape = source_set.tile_shape
	tile_set.tile_layout = source_set.tile_layout
	tile_set.tile_offset_axis = source_set.tile_offset_axis
	tile_set.tile_size = source_set.tile_size

	var size: Vector2i = source_set.tile_size
	var corners: PackedVector2Array = geometry.corner_offsets()
	var inradius: float = INF
	for i: int in corners.size():
		inradius = minf(inradius, _distance_to_line(Vector2.ZERO, corners[i], corners[(i + 1) % corners.size()]))

	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half: Vector2 = Vector2(size) / 2.0
	for y: int in size.y:
		for x: int in size.x:
			var point: Vector2 = Vector2(x, y) + Vector2(0.5, 0.5) - half
			if not Geometry2D.is_point_in_polygon(point, corners):
				continue
			var distance: float = INF
			for i: int in corners.size():
				distance = minf(distance, _distance_to_line(point, corners[i], corners[(i + 1) % corners.size()]))
			var value: float = clampf(distance / inradius, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, value, value, 1.0))

	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = size
	source.create_tile(Vector2i.ZERO)
	# drawn at (cell center - region / 2 - origin), this puts the gradient on the hex art
	source.get_tile_data(Vector2i.ZERO, 0).texture_origin = Vector2i(-geometry.art_offset.round())
	tile_set.add_source(source, 0)
	return tile_set


static func _distance_to_line(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
