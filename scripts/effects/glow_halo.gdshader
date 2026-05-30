shader_type canvas_item;
render_mode blend_add, unshaded;

// Reusable additive BLOOM glow. Applied to a "glow node" sitting BEHIND a
// projectile/sprite (z_index -1), scaled larger than the host so a soft halo
// can fade outward past the host's edges. The glow samples the host's own
// texture (the builtin TEXTURE) and tints it with a CPU-derived color, so a
// magenta bullet glows magenta, a cyan bolt cyan, etc. — see glow_shader_fx.gd
// for how the color is picked.
//
// SOFT BLOOM, NOT AN OUTLINE
//   The old version did a single linear-filtered texture tap on an upscaled
//   quad, which just reads as a crisp scaled silhouette / outline. Instead we
//   now do a fixed multi-tap BLUR of the sprite's ALPHA: many samples on
//   concentric rings, distance-weighted (gaussian), accumulated and
//   normalized. That spreads the alpha into a soft diffuse haze that is
//   brightest near the sprite and fades smoothly to transparent — a light
//   bloom, like the old radial GradientTexture2D glow.
//
// QUAD INSET (room for the bloom to fade into)
//   Bullet art is edge-to-edge alpha (no transparent padding), so a blur in
//   raw UV would clamp to a hard rectangle at the texture boundary. The host
//   script scales this quad up by `quad_scale` per axis and we INSET the
//   sampled UV so the sprite sits at native size, centered, with transparent
//   margin all around. The bloom fades into that margin and reaches zero
//   BEFORE the quad edge — so it is never cut off. Out-of-[0,1] taps are
//   forced to 0 alpha (not the clamped edge) so the haze is round, not boxed.
//
// Tuning knobs live on the host script as uniforms (DRY: no per-weapon shader
// edits). `intensity` scales overall additive brightness; `blur_px` is the
// bloom reach in native texture pixels; `falloff` shapes core-vs-tail; the
// host passes `quad_scale` (per-axis) to undo the node upscale for sampling.
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 0.55;
// Bloom reach in native texture pixels. Each ring extends this far.
uniform float blur_px = 3.5;
// Falloff exponent applied to the accumulated alpha. >1 keeps a brighter core
// with a faster-fading tail (more "bloom"); ~1 is a flatter haze.
uniform float falloff = 1.6;
// Per-axis factor that maps this enlarged quad's UV back to the native sprite
// rect. = (native_px + 2*margin_px) / native_px, supplied per instance.
uniform vec2 quad_scale = vec2(1.0, 1.0);

// 16 ring directions (two rings of 8) + center. Fixed count for gl_compat.
const int RING_COUNT = 16;
const vec2 RING[16] = {
	// inner ring (8 dirs, radius 0.5 of blur reach)
	vec2( 0.5,  0.0), vec2( 0.354,  0.354), vec2( 0.0,  0.5), vec2(-0.354,  0.354),
	vec2(-0.5,  0.0), vec2(-0.354, -0.354), vec2( 0.0, -0.5), vec2( 0.354, -0.354),
	// outer ring (8 dirs, radius 1.0 of blur reach)
	vec2( 1.0,  0.0), vec2( 0.707,  0.707), vec2( 0.0,  1.0), vec2(-0.707,  0.707),
	vec2(-1.0,  0.0), vec2(-0.707, -0.707), vec2( 0.0, -1.0), vec2( 0.707, -0.707)
};

void fragment() {
	// Map this enlarged quad's UV back onto the native sprite rect, centered.
	// Pixels in the surrounding margin land outside [0,1] and read alpha 0.
	vec2 tuv = (UV - 0.5) * quad_scale + 0.5;

	// Blur reach expressed in this node's UV space (TEXTURE_PIXEL_SIZE is the
	// native sprite's per-texel UV step).
	vec2 reach = TEXTURE_PIXEL_SIZE * blur_px;

	// Center tap (weight 1.0). Sampling MUST be inlined here: in gl_compat the
	// builtin TEXTURE is only valid inside fragment(), not in a helper fn.
	float ci = step(0.0, tuv.x) * step(tuv.x, 1.0) * step(0.0, tuv.y) * step(tuv.y, 1.0);
	float acc = texture(TEXTURE, tuv).a * ci;
	float wsum = 1.0;
	// Inner ring weight ~0.6, outer ring weight ~0.3 (gaussian-ish falloff).
	// Each tap returns 0 outside [0,1] so the haze is a round disc, not clamped
	// to the texture's rectangular edge.
	for (int i = 0; i < RING_COUNT; i++) {
		vec2 suv = tuv + RING[i] * reach;
		float w = (i < 8) ? 0.6 : 0.3;
		float inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
		acc += texture(TEXTURE, suv).a * inside * w;
		wsum += w;
	}
	float a = acc / wsum;

	// Shape the spread into a bloom: brighter core, smooth fade to transparent.
	a = pow(clamp(a, 0.0, 1.0), falloff);

	COLOR = vec4(glow_color.rgb, a * intensity * glow_color.a);
}
