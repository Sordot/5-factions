shader_type canvas_item;

// Seamless tiled floor shader for the Vat Basin (GENESIS_V2) biome.
// Blends tiled samples with subtle world-space macro tonal & moss modulation
// so repeated conduits and panels never read as an obvious grid across large arenas,
// while staying strictly below HDR bloom threshold (1.0) for crisp unit readability.

uniform sampler2D floor_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 arena_origin = vec2(-1300.0, -950.0);
uniform vec2 arena_size = vec2(2600.0, 1900.0);
uniform float tile_world_size = 512.0;

uniform float brightness_scale = 0.42;
uniform float contrast_gain = 0.92;
uniform float saturation_scale = 0.78;
uniform float macro_variation = 0.075;
uniform vec3 shadow_tint : source_color = vec3(0.032, 0.068, 0.098);
uniform vec3 moss_tint : source_color = vec3(0.055, 0.145, 0.095);
uniform vec3 coolant_tint : source_color = vec3(0.065, 0.245, 0.275);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = value_noise(p) * 0.65;
	v += value_noise(p * 2.03 + vec2(17.1, 31.7)) * 0.35;
	return v;
}

void fragment() {
	vec2 world_pos = arena_origin + UV * arena_size;
	float inv_tile = 1.0 / max(tile_world_size, 64.0);
	vec2 tile_uv = world_pos * inv_tile;

	// Primary crisp tiled sample (repeat_enable prevents edge clamping).
	vec3 tex_col = texture(floor_tex, tile_uv).rgb;

	// Low-frequency world-space macro noise for organic anti-repetition modulation.
	float n_macro = fbm2(world_pos * 0.00135 + vec2(3.1, 7.4));
	float n_moss = fbm2(world_pos * 0.00215 + vec2(19.7, 11.3));
	float n_detail = value_noise(world_pos * 0.0048 + vec2(5.2, 23.8));

	// Subtle secondary rotated mip-softened sample blended lightly only for organic tonal break-up.
	vec2 rot_uv = vec2(-world_pos.y, world_pos.x) * (inv_tile * 0.73) + vec2(0.37, 0.61);
	vec3 soft_var = textureLod(floor_tex, rot_uv, 2.5).rgb;
	tex_col = mix(tex_col, soft_var, 0.08 * smoothstep(0.35, 0.85, n_moss));

	// Detect moss (green-dominant) and aqua coolant conduits (cyan/blue-dominant) to grade cleanly.
	float lum = dot(tex_col, vec3(0.299, 0.587, 0.114));
	float moss_mask = clamp((tex_col.g - max(tex_col.r, tex_col.b) * 0.92) * 3.2, 0.0, 1.0);
	float coolant_mask = clamp((min(tex_col.g, tex_col.b) - tex_col.r * 1.15) * 3.0, 0.0, 1.0);

	// Controlled saturation & contrast grading for strong RTS figure-ground separation.
	vec3 graded = mix(vec3(lum), tex_col, saturation_scale);
	graded = (graded - 0.5) * contrast_gain + 0.5;
	graded = max(graded, vec3(0.0));
	graded = mix(shadow_tint, graded, 0.86) * brightness_scale;

	// Apply smooth ~6-8% world-space tonal and moss/coolant warmth drift.
	float tone_shift = 1.0 + ((n_macro - 0.5) * 2.0 * macro_variation) + ((n_detail - 0.5) * 0.035);
	graded *= tone_shift;
	graded = mix(graded, graded + moss_tint * 0.22, moss_mask * smoothstep(0.38, 0.78, n_moss));
	graded = mix(graded, graded + coolant_tint * 0.24, coolant_mask * (0.45 + 0.55 * n_macro));

	// Keep output strictly in dark SDR range (< 0.72) so terrain never triggers HDR bloom.
	COLOR = vec4(clamp(graded, vec3(0.012, 0.024, 0.036), vec3(0.68)), 1.0);
}
