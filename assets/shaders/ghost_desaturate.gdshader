shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 0.28;
uniform float brightness : hint_range(0.0, 1.5) = 0.74;
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.88;

void fragment() {
	vec4 col = COLOR;
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(vec3(luma), col.rgb, saturation) * brightness;
	COLOR = vec4(desat, col.a * alpha_scale);
}
