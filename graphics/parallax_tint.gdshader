// Multiplicative tint for an entire CanvasGroup. The CanvasGroup
// composites its children into one offscreen texture; this shader then
// samples that texture and multiplies by `tint`. Unlike the old
// silhouette shader (which REPLACED color), this preserves the layer's
// art and just tints it — same semantics as CanvasItem.modulate, but
// reliable inside a Parallax2D parent (where modulate doesn't always
// propagate to tiled repeat draws in Godot 4.3).
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(tex_color.rgb * tint.rgb, tex_color.a * tint.a);
}
