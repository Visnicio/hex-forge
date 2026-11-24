// Splits a tile's art in two: the part that sticks out ABOVE its own hex (a mountain peak or a tower
// invading the row behind) and everything else (the hex itself and its base/rim).
// keep_overhang = true: used by OverhangPass to redraw the peaks on top of roads/rivers, so paths stay
//   above the ground but below the tall art.
// keep_overhang = false: used by GroundBlend so the biome smoothing only warps the hexes, never the peaks.
shader_type canvas_item;

uniform bool keep_overhang = true;

// atlas texture size in pixels
uniform vec2 atlas_size;
// size of each tile region in the atlas, its margins and separation
uniform vec2 region_size;
uniform vec2 margins;
uniform vec2 separation;
// center of the hex art inside a tile region, in region pixels
uniform vec2 hex_center;
// hex corners relative to hex_center (slightly enlarged so the hex outline itself isnt redrawn)
uniform vec2 corners[6];

void fragment() {
	vec2 atlas_px = UV * atlas_size - margins;
	vec2 local = mod(atlas_px, region_size + separation) - hex_center;

	bool overhang = local.y <= 0.0;

	// convex polygon test that works with either winding
	float min_cross = 1e20;
	float max_cross = -1e20;
	for (int i = 0; i < 6; i++) {
		vec2 a = corners[i];
		vec2 edge = corners[(i + 1) % 6] - a;
		vec2 to_point = local - a;
		float cross_value = edge.x * to_point.y - edge.y * to_point.x;
		min_cross = min(min_cross, cross_value);
		max_cross = max(max_cross, cross_value);
	}
	bool inside = min_cross >= 0.0 || max_cross <= 0.0;
	overhang = overhang && !inside;
	if (overhang != keep_overhang) {
		discard;
	}
}
