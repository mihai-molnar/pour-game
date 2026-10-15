shader_type canvas_item;

// Liquid seen through a glass wall, rendered at native pixel resolution.
// The background is sampled from the screen with a lens + wobble offset
// (whole pixels only, so it stays crisp), then tinted by how much liquid
// the view ray crosses (thicker in the middle of a round vessel).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.0, 0.6, 0.86, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.5;
uniform float refraction_px = 1.0;
uniform float lens_strength : hint_range(-1.0, 1.0) = 0.3;
// 0 = smooth tint; otherwise the tint is quantized to this many steps with ordered dithering
uniform float dither_levels = 4.0;
uniform vec4 highlight : source_color = vec4(1.0);
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.45;

// Geometry in the vessel's local pixels, set by the vessel script.
uniform float center_x = 0.0;
uniform float half_width = 19.0;
uniform float surface_y = 0.0;
uniform float highlight_x = -15.0;

varying vec2 local_pos;
varying vec2 axis_x; // local +x expressed in screen pixels (handles rotation)

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	local_pos = VERTEX;
	axis_x = (CANVAS_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
}

void fragment() {
	vec2 p = floor(local_pos) + 0.5;
	float rel = clamp((p.x - center_x) / half_width, -1.0, 1.0);
	float thickness = sqrt(1.0 - rel * rel);

	float wobble = sin(p.y * 0.55 + TIME * 2.4) * 0.6 + sin(p.y * 0.21 + p.x * 0.3 - TIME * 1.1) * 0.4;
	float shift = (center_x - p.x) * lens_strength + wobble * refraction_px;
	vec2 offset = round(axis_x * shift);
	vec3 behind = texture(screen_tex, SCREEN_UV + offset * SCREEN_PIXEL_SIZE).rgb;

	float depth = clamp((p.y - surface_y) / 70.0, 0.0, 1.0);
	float amount = tint_strength * mix(0.55, 1.0, thickness) * mix(0.85, 1.15, depth);
	if (dither_levels > 0.0) {
		ivec2 q = ivec2(mod(FRAGCOORD.xy, 4.0));
		float threshold = (BAYER[q.y * 4 + q.x] + 0.5) / 16.0;
		amount = floor(amount * dither_levels + threshold) / dither_levels;
	}
	vec3 col = mix(behind, tint.rgb, clamp(amount, 0.0, 1.0));
	if (abs(p.x - highlight_x) < 0.6) {
		col = mix(col, highlight.rgb, highlight_strength);
	}
	COLOR = vec4(col, 1.0);
}
