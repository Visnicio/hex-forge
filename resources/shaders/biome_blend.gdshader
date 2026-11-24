// Biome smoothing (GroundBlend): the ground layers are rendered to a texture, this redraws it with the reads
// pushed around by noise ("domain warping") ONLY near the hex borders, so the straight edges between biomes
// become organic while the middle of every tile stays untouched.
// edge_mask comes from a ghost tilemap with a center->border gradient tile (1 at the center, 0 on the border).
shader_type canvas_item;

// nearest: the composite maps 1 texel to 1 screen pixel, linear would blur the untouched hex centers
uniform sampler2D ground_texture : filter_nearest, repeat_disable;
uniform sampler2D edge_mask : filter_linear, repeat_disable;
// 0 = off, 1 = full
uniform float strength : hint_range(0.0, 1.0) = 0.6;
// width of the band near the border that gets warped, in fraction of the distance center->border
uniform float band : hint_range(0.05, 1.0) = 0.32;
// how much color bleeds across the border inside the band
uniform float bleed : hint_range(0.0, 1.0) = 0.25;
// world position of the top-left of the screen, world units per screen pixel, screen size in pixels
uniform vec2 world_origin;
uniform float world_per_pixel = 1.0;
uniform vec2 screen_size = vec2(1.0);
// hex size in world units (so the noise and the warp scale with the tileset)
uniform float hex_world_size = 64.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.13 + 7.7) * 0.35;
}

void fragment() {
	vec4 mask = texture(edge_mask, UV);
	// outside every hex counts as border, so the map outline also gets organic
	float distance_to_edge = mask.a > 0.5 ? mask.r : 0.0;
	float edge = 1.0 - smoothstep(0.0, band, distance_to_edge);

	vec2 world = world_origin + UV * screen_size * world_per_pixel;
	vec2 noise_position = world / hex_world_size * 3.0;
	vec2 warp = vec2(fbm(noise_position), fbm(noise_position + vec2(31.4, 17.9))) * 2.0 - 1.0;

	// up to ~15% of a hex at full strength, converted from world units to UV
	vec2 offset_world = warp * hex_world_size * 0.15 * strength * edge;
	vec2 offset_uv = offset_world / world_per_pixel / screen_size;
	vec4 base = texture(ground_texture, UV);
	vec4 color = texture(ground_texture, UV + offset_uv);
	// the peaks of tall tiles are cut out of this texture (OverhangPass draws them crisp on top), dont drag those
	// holes around: inside the map a transparent read keeps the original pixel, only the map outline gets ragged
	if (color.a < 0.5 && base.a > 0.5) {
		color = base;
	}

	if (bleed > 0.0 && edge > 0.0) {
		vec2 radius = vec2(hex_world_size * 0.06) / world_per_pixel / screen_size;
		vec4 blurred = (texture(ground_texture, UV + offset_uv + vec2(radius.x, 0.0))
			+ texture(ground_texture, UV + offset_uv - vec2(radius.x, 0.0))
			+ texture(ground_texture, UV + offset_uv + vec2(0.0, radius.y))
			+ texture(ground_texture, UV + offset_uv - vec2(0.0, radius.y))) * 0.25;
		color = mix(color, blurred, bleed * edge * strength * step(0.01, blurred.a));
	}
	COLOR = color;
}
