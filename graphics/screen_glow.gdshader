// Screen-space 2D glow (no WorldEnvironment) — evaluated from
// https://godotshaders.com/shader/2d-glow-screen-no-worldenvironment-node/
// (CC0, "3boood_pro") and REWRITTEN for Starblaster (2026-06-10):
//   - the original's brightness threshold was a no-op without HDR 2D
//     (`pixel.rgb <= 1.0` is always true in LDR) → real luminance threshold
//     with a soft knee, works at our standard LDR pipeline;
//   - the original's 65-weight × 12-tap loop (~780 taps/px) → a mip-pyramid
//     bloom: hint_screen_texture with mipmaps gives pre-blurred copies of the
//     frame for free, so a handful of textureLod taps buys a wide soft glow.
//     Cheap at the 480×270 internal viewport.
//
// SETUP: full-viewport ColorRect drawn AFTER the content it should bloom
// (last child of the viewport / its own CanvasLayer), this material on it.
// Everything brighter than `threshold` blooms — scene-wide, unlike a per-sprite
// glow (glow_fx.gd radial halo / glow_effect_2d in-sprite emission).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Luminance floor: pixels below it contribute nothing.
uniform float threshold : hint_range(0.0, 1.0) = 0.6;
// Soft shoulder above the threshold (avoids hard bloom pop-in).
uniform float knee : hint_range(0.01, 0.5) = 0.2;
uniform float intensity : hint_range(0.0, 4.0) = 1.2;
// Highest mip level sampled: each +1 doubles the glow radius.
uniform int max_lod : hint_range(1, 6) = 4;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

vec3 thresholded(vec3 c) {
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	return c * smoothstep(threshold, threshold + knee, lum);
}

void fragment() {
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	// Skip LOD 0 (the sharp frame) — additive identity would just over-brighten.
	for (int i = 1; i <= max_lod; i++) {
		float w = 1.0 / float(i);
		acc += thresholded(textureLod(screen_texture, SCREEN_UV, float(i)).rgb) * w;
		wsum += w;
	}
	acc /= max(wsum, 0.001);
	COLOR = vec4(acc * tint.rgb * intensity, 1.0);
}
