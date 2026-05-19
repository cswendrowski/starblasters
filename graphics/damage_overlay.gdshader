shader_type canvas_item;

// Damage shader (Roman, 2026-05-18): "darken sprites and fray the outer
// edges of the sprites via transparency so that we can make sprites
// progressively more damaged looking as their hull drops."
//
// Two effects, both driven by `damage_level` ∈ [0, 1]:
//   1. Darken — multiply RGB by 1 - 0.55 * damage_level so heavily-damaged
//      sprites look scorched.
//   2. Fray — sample a per-pixel noise function; pixels whose noise score
//      drops below a threshold proportional to damage_level get their
//      alpha zeroed. This produces a chipped/ragged outline at high
//      damage without needing per-sprite art variants.
//
// The fray is biased to the outer edge of the sprite by mixing in distance
// from center, so the middle stays mostly intact while the silhouette
// gets chewed up.

uniform float damage_level : hint_range(0.0, 1.0) = 0.0;
uniform float darken_strength : hint_range(0.0, 1.0) = 0.55;
uniform float fray_strength : hint_range(0.0, 1.0) = 0.75;
uniform vec4 burn_tint : source_color = vec4(0.55, 0.30, 0.18, 1.0);

// Cheap 2D hash. Stable per-pixel; same input → same output, but no
// per-pixel array uniforms.
float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	if (src.a < 0.01) {
		COLOR = src;
	} else {
		// Distance from sprite center — used to bias fray toward edges.
		// UV is 0..1 across the texture; (UV - 0.5) is centered ±0.5.
		float edge_dist = length(UV - vec2(0.5)) * 2.0; // 0 center, ~1.4 corner
		// Per-pixel noise score in [0, 1]. Quantize to texel positions so
		// the fray reads as chunky pixel chips, not fine grain.
		vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
		vec2 pixel_pos = floor(UV * tex_size);
		float noise = hash2(pixel_pos);
		// Threshold rises with damage_level AND with distance from center.
		// At full damage, edge pixels need a noise > 0.4 to survive; center
		// pixels stay intact (their threshold is ~0).
		float threshold = damage_level * fray_strength * clamp(edge_dist, 0.0, 1.0);
		float alpha_keep = step(threshold, noise);
		// Darken + burn tint shift, scaled by damage_level.
		vec3 darkened = mix(src.rgb, src.rgb * burn_tint.rgb, damage_level * 0.5);
		darkened *= 1.0 - darken_strength * damage_level;
		COLOR = vec4(darkened, src.a * alpha_keep);
	}
}
