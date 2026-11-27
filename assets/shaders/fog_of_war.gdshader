shader_type canvas_item;

uniform vec2 grid_size = vec2(82.0, 60.0);
uniform vec2 arena_size = vec2(2600.0, 1900.0);
uniform vec4 color_unexplored : source_color = vec4(0.015, 0.025, 0.045, 0.93);
uniform vec4 color_explored : source_color = vec4(0.025, 0.045, 0.080, 0.48);

void fragment() {
	vec2 texel = 1.0 / max(grid_size, vec2(1.0));
	vec2 uv_c = clamp(UV, vec2(0.0), vec2(1.0));

	// 9-tap tent/Gaussian filter across the 32px world fog RG8 grid for organic vision arcs.
	vec2 s_c  = texture(TEXTURE, uv_c).rg * 0.28;
	vec2 s_n  = texture(TEXTURE, clamp(uv_c + vec2(0.0, -texel.y), vec2(0.0), vec2(1.0))).rg * 0.12;
	vec2 s_s  = texture(TEXTURE, clamp(uv_c + vec2(0.0,  texel.y), vec2(0.0), vec2(1.0))).rg * 0.12;
	vec2 s_w  = texture(TEXTURE, clamp(uv_c + vec2(-texel.x, 0.0), vec2(0.0), vec2(1.0))).rg * 0.12;
	vec2 s_e  = texture(TEXTURE, clamp(uv_c + vec2( texel.x, 0.0), vec2(0.0), vec2(1.0))).rg * 0.12;
	vec2 s_nw = texture(TEXTURE, clamp(uv_c + vec2(-texel.x, -texel.y), vec2(0.0), vec2(1.0))).rg * 0.06;
	vec2 s_ne = texture(TEXTURE, clamp(uv_c + vec2( texel.x, -texel.y), vec2(0.0), vec2(1.0))).rg * 0.06;
	vec2 s_sw = texture(TEXTURE, clamp(uv_c + vec2(-texel.x,  texel.y), vec2(0.0), vec2(1.0))).rg * 0.06;
	vec2 s_se = texture(TEXTURE, clamp(uv_c + vec2( texel.x,  texel.y), vec2(0.0), vec2(1.0))).rg * 0.06;

	vec2 smoothed = s_c + s_n + s_s + s_w + s_e + s_nw + s_ne + s_sw + s_se;
	float vis_val = smoothed.r;

	float explored_t = smoothstep(0.08, 0.46, vis_val);
	float visible_t = smoothstep(0.54, 0.92, vis_val);

	vec4 base_fog = mix(color_unexplored, color_explored, explored_t);
	base_fog = mix(base_fog, vec4(0.0, 0.0, 0.0, 0.0), visible_t);

	COLOR = base_fog;
}
