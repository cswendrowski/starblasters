shader_type canvas_item;
render_mode blend_mul;

float getAlpha(float col, float alpha) {
	return col + (1.0 - col) * alpha;
}

void fragment() {
	vec3 tex = texture(TEXTURE, UV).rgb;
	float alpha = 1.0 - COLOR.a;
	
	COLOR.rgb = vec3(
		getAlpha(tex.r, alpha),
		getAlpha(tex.g, alpha),
		getAlpha(tex.b, alpha)
	);
}