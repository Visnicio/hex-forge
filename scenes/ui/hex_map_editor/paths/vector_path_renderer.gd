## Draws paths as vector lines, works with ANY tileset since it only needs the hex geometry.[br]
## - meander: each segment is wiggled by midpoint displacement seeded by (map seed + the segment's own key),
##   so editing one segment never moves the others[br]
## - Chaikin smoothing (local, so it also only touches the neighbors of an edited segment)[br]
## - rivers get wider from the source (first point) to the mouth (last point)[br]
## - dashed lines are cut by arc length so dashes keep the same size on curves
class_name VectorPathRenderer extends PathRenderer


func build(path: PathData, geometry: HexGeometry, seed: int) -> Node2D:
	var line: PackedVector2Array = centerline(path, geometry, seed)
	if line.size() < 2:
		return null

	var style: PathStyle = PathStyles.resolve(path.style_id, path.kind)
	var unit: float = geometry.unit_size()
	var root: Node2D = Node2D.new()
	root.name = path.id

	if style.dash_length > 0.0 and style.gap_length > 0.0:
		var dashes: DashedLine = DashedLine.new()
		dashes.setup(line, style, unit)
		root.add_child(dashes)
	else:
		if style.outline_width > 0.0:
			root.add_child(make_line(line, style, unit, true))
		root.add_child(make_line(line, style, unit, false))
	return root


func centerline(path: PathData, geometry: HexGeometry, seed: int) -> PackedVector2Array:
	if path.points.size() < 2 or not geometry.is_valid():
		return PackedVector2Array()

	var style: PathStyle = PathStyles.resolve(path.style_id, path.kind)
	var result: PackedVector2Array = [point_position(path, 0, geometry)]
	for i: int in path.points.size() - 1:
		var segment: PackedVector2Array = meander_segment(
			point_position(path, i, geometry), point_position(path, i + 1, geometry),
			path.point_key(i), path.point_key(i + 1), style, seed)
		for j: int in range(1, segment.size()): # first point is the end of the previous segment
			result.append(segment[j])

	return chaikin(result, style.smoothing_iterations)


static func point_position(path: PathData, index: int, geometry: HexGeometry) -> Vector2:
	if path.anchor == PathData.Anchor.CELL:
		return geometry.cell_center(path.points[index])
	return geometry.vertex_position(path.points[index])


## Wiggled version of the segment a-b, the same 2 keys always give the same shape no matter the direction
## the path goes through it (the displacement is generated in a canonical direction and reversed if needed)
static func meander_segment(a: Vector2, b: Vector2, key_a: String, key_b: String, style: PathStyle, seed: int) -> PackedVector2Array:
	var reversed: bool = key_a > key_b
	var start: Vector2 = b if reversed else a
	var end: Vector2 = a if reversed else b

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%s" % [seed, mini_key(key_a, key_b), maxi_key(key_a, key_b)])

	var points: PackedVector2Array = [start, end]
	var amplitude: float = style.meander_amplitude * start.distance_to(end)
	for _level: int in style.meander_depth:
		var next: PackedVector2Array = [points[0]]
		for i: int in points.size() - 1:
			var p: Vector2 = points[i]
			var q: Vector2 = points[i + 1]
			var normal: Vector2 = (q - p).orthogonal().normalized()
			next.append((p + q) * 0.5 + normal * rng.randf_range(-1.0, 1.0) * amplitude)
			next.append(q)
		points = next
		amplitude *= 0.5

	if reversed:
		points.reverse()
	return points


static func mini_key(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_key(a: String, b: String) -> String:
	return b if a < b else a


## Corner cutting, keeps the first and last points so paths still start/end on their cell/corner
static func chaikin(points: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var result: PackedVector2Array = points
	for _iteration: int in iterations:
		if result.size() < 3:
			return result
		var next: PackedVector2Array = [result[0]]
		for i: int in result.size() - 1:
			next.append(result[i].lerp(result[i + 1], 0.25))
			next.append(result[i].lerp(result[i + 1], 0.75))
		next.append(result[result.size() - 1])
		result = next
	return result


## Width of the fill at the start/end of the line, in tile pixels
static func fill_widths(style: PathStyle, unit: float) -> Vector2:
	var base: float = style.width * unit
	return Vector2(base * style.width_start_multiplier, base * style.width_end_multiplier)


## Line2D of the fill or of the outline of a path, [param taper] applies the start/end width multipliers
static func make_line(points: PackedVector2Array, style: PathStyle, unit: float, is_outline: bool, taper: bool = true) -> Line2D:
	var line: Line2D = Line2D.new()
	line.points = points
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true

	var widths: Vector2 = fill_widths(style, unit) if taper else Vector2.ONE * style.width * unit
	var extra: float = style.outline_width * unit * 2.0 if is_outline else 0.0
	var start_width: float = widths.x + extra
	var end_width: float = widths.y + extra
	var max_width: float = maxf(start_width, end_width)
	line.width = max_width

	if not is_equal_approx(start_width, end_width):
		var curve: Curve = Curve.new()
		curve.add_point(Vector2(0.0, start_width / max_width))
		curve.add_point(Vector2(1.0, end_width / max_width))
		line.width_curve = curve

	if is_outline:
		line.default_color = style.outline_color
	else:
		line.default_color = style.color
		if style.texture != null:
			line.texture = style.texture
			line.texture_mode = Line2D.LINE_TEXTURE_TILE
	return line


## Dashes cut along the arc length, drawn with an outline under each dash
class DashedLine extends Node2D:
	var _dashes: Array[PackedVector2Array] = []
	var _style: PathStyle
	var _unit: float

	func setup(points: PackedVector2Array, style: PathStyle, unit: float) -> void:
		_style = style
		_unit = unit
		_dashes = _cut_dashes(points, style.dash_length * unit, style.gap_length * unit)
		queue_redraw()

	func _draw() -> void:
		var width: float = _style.width * _unit
		if _style.outline_width > 0.0:
			for dash: PackedVector2Array in _dashes:
				draw_polyline(dash, _style.outline_color, width + _style.outline_width * _unit * 2.0, true)
		for dash: PackedVector2Array in _dashes:
			draw_polyline(dash, _style.color, width, true)

	static func _cut_dashes(points: PackedVector2Array, dash: float, gap: float) -> Array[PackedVector2Array]:
		var result: Array[PackedVector2Array] = []
		var current: PackedVector2Array = [points[0]]
		var drawing: bool = true
		var remaining: float = dash # length left in the current dash or gap
		for i: int in points.size() - 1:
			var p: Vector2 = points[i]
			var q: Vector2 = points[i + 1]
			var segment_length: float = p.distance_to(q)
			var travelled: float = 0.0
			while segment_length - travelled > remaining:
				travelled += remaining
				var cut: Vector2 = p.lerp(q, travelled / segment_length)
				if drawing:
					current.append(cut)
					result.append(current)
				else:
					current = [cut]
				drawing = not drawing
				remaining = dash if drawing else gap
			remaining -= segment_length - travelled
			if drawing:
				current.append(q)
		if drawing and current.size() >= 2:
			result.append(current)
		return result
