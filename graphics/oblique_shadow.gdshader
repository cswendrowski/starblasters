// 2D Top-Down Oblique Shadow — authored fresh.
// Canonical reference: https://godotshaders.com/shader/2d-top-down-oblique-shadow/
// (Reference shader requires per-sprite height maps which we don't author for
// our 16x16 pixel-art assets; this version reproduces the high-sun drop-shadow
// look using only the sprite's alpha channel. Sample the source texture, skew
// the UV in screen-space pixels via TEXTURE_PIXEL_SIZE, threshold the alpha,
// and emit a soft-edged dark blob behind the host sprite.)
//
// Intended usage: attached by scripts/shadow_fx.gd to a Sprite2D child whose
// z_index < its parent. The child shares the host sprite's texture so the
// silhouette matches automatically as the parent's frame / animation changes.

shader_type canvas_item;

uniform vec4 shadow_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Opacity of the densest part of the shadow blob (0..1).
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.4;

// Offset of the shadow in *texture pixels* — applied to the lookup UV before
// alpha-sampling. shadow_fx.gd passes the world-space pixel offset divided by
// host scale so the shadow appears N world-pixels down-right regardless of
// the host's scale chain.
uniform vec2 shadow_offset_px = vec2(3.0, 3.0);

// Softness radius (in source-texture pixels) for the alpha-feathered edge.
uniform float softness_px : hint_range(0.0, 8.0) = 1.5;

// Alpha threshold above which the host sprite is considered opaque enough to
// cast shadow. Keeps anti-aliased fringes from doubling the silhouette.
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	// Shift the sample point opposite to the desired shadow direction so the
	// shadow visually lands at +shadow_offset_px from the host sprite.
	vec2 sample_uv = UV - shadow_offset_px * px;

	// Center silhouette
	float a = texture(TEXTURE, sample_uv).a;
	float core = step(alpha_cutoff, a);

	// 4-tap box blur in source-pixel units for soft edges. Cheap and stays
	// crisp at the chunky 16x16 source scale (host is upscaled 3x downstream).
	vec2 s = px * softness_px;
	float e = 0.0;
	e += texture(TEXTURE, sample_uv + vec2( s.x, 0.0)).a;
	e += texture(TEXTURE, sample_uv + vec2(-s.x, 0.0)).a;
	e += texture(TEXTURE, sample_uv + vec2(0.0,  s.y)).a;
	e += texture(TEXTURE, sample_uv + vec2(0.0, -s.y)).a;
	e *= 0.25;

	// Combine: core silhouette + softened halo, clamped to 1.
	float mask = clamp(max(core, e * 0.85), 0.0, 1.0);

	// Discard fully-transparent pixels so the shadow doesn't paint a square box.
	if (mask <= 0.001) {
		discard;
	}

	COLOR = vec4(shadow_tint.rgb, shadow_tint.a * shadow_opacity * mask);
}
