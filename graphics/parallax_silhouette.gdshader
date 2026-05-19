shader_type canvas_item;

uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	// Overwrite the texture's color while preserving its alpha cutout
	COLOR = vec4(silhouette_color.rgb, tex_color.a);
}
