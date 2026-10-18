shader_type canvas_item;

// Liquid seen through a glass wall. The bar behind it is sampled from the
// screen, bent the way a liquid-filled cylinder bends it (a lens that
// magnifies toward the middle, strongest near the walls, wobbling while the
// surface moves), then tinted by how much liquid the eye looks through
// (Beer-Lambert absorption: thickest across the middle of a round vessel,
// a little deeper toward the bottom), plus the colour the liquid gives off by
// itself. Smooth: no pixel rounding, no dithering.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Look, per drink (set by the vessel scripts from the DrinkDef).
uniform vec4 tint : source_color = vec4(0.0, 0.6, 0.86, 1.0);
uniform vec3 absorb = vec3(0.010, 0.004, 0.002);  // per px of view path, per channel
uniform float scatter : hint_range(0.0, 1.0) = 0.35;
// Look, per vessel (in the materials in main.tscn).
uniform float lens_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wobble_px = 0.6;
uniform float edge_glow : hint_range(0.0, 1.0) = 0.2;

// Geometry in the vessel's local px, set by the vessel script.
uniform float center_x = 0.0;
uniform float half_width = 19.0;
uniform float surface_y = 0.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos;
	float rel = clamp((p.x - center_x) / half_width, -1.0, 1.0);
	float chord = sqrt(max(1.0 - rel * rel, 0.0));
	float path = 2.0 * half_width * chord;
	float depth = clamp((p.y - surface_y) / 70.0, 0.0, 1.0);

	// A shift along the vessel's own x axis (it may be tilted), turned into a
	// screen-UV offset with the local -> screen derivatives, so it holds at any
	// window size, zoom or rotation.
	float wobble = sin(p.y * 0.55 + TIME * 2.4) * 0.6 + sin(p.y * 0.21 + p.x * 0.3 - TIME * 1.1) * 0.4;
	float shift = (center_x - p.x) * lens_strength * (0.6 + 0.4 * rel * rel) + wobble * wobble_px;
	mat2 to_local = mat2(dFdx(p), dFdy(p));
	mat2 to_uv = mat2(dFdx(SCREEN_UV), dFdy(SCREEN_UV));
	vec2 uv = SCREEN_UV + to_uv * inverse(to_local) * vec2(shift, 0.0);
	vec3 behind = textureLod(screen_tex, uv, 0.0).rgb;

	vec3 trans = exp(-absorb * path * mix(1.0, 1.25, depth));
	vec3 col = behind * trans + tint.rgb * scatter * (0.5 + 0.5 * chord) * mix(1.1, 0.8, depth);
	col += vec3(smoothstep(0.86, 1.0, abs(rel)) * edge_glow);
	COLOR = vec4(col, 1.0);
}
