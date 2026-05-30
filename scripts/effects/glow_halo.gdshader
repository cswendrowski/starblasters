shader_type canvas_item;
render_mode blend_add, unshaded;

// Reusable additive halo glow. Applied to a "glow node" sitting BEHIND a
// projectile/sprite (z_index -1), scaled slightly larger than the host so
// the soft silhouette extends a couple pixels past the host edges. The
// glow samples the host's own texture (passed in as `tex`) and tints it
// with a CPU-derived color, so a magenta bullet glows magenta, a cyan bolt
// cyan, etc. — see glow_shader_fx.gd for how the color is picked.
//
// Tuning knobs live on the host script as uniforms (DRY: no per-weapon
// shader edits). `intensity` scales overall alpha. Softness comes from
// sampling the builtin TEXTURE with a linear filter (filter_linear_hint on
// the glow node's texture_filter) which spreads the upscaled silhouette
// edge into a halo with no multi-tap blur loop (cheap — these spawn a lot).
//
// We sample the BUILTIN `TEXTURE` (not a `tex` uniform) so AtlasTexture
// regions and Sprite2D hframes/region are handled by the engine — UV is
// already frame-local, so the silhouette matches the shown frame.
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 0.6;

void fragment() {
	// Sample the host silhouette. Because this quad is scaled up relative to
	// the host texture, the linear filter spreads the alpha edge outward,
	// producing the soft 2-3px halo.
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(glow_color.rgb, a * intensity * glow_color.a);
}
