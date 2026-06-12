shader_type canvas_item;

// Combat post-FX (Roman renderer-polish D). One screen-reading pass on a playfield-band
// rect carrying a single Forward+-affordable sweetener:
//   * chromatic aberration — R/B channels split outward, driven by `aberration` (raised
//     while an aggressive Shift-mode is engaged: hyper overcharge / phase dash).
// Band-limited by the host rect (X 132-348) so the HUD + glass gutters never warp.
// (D1 heat-haze shimmer + D2 radial ripple both RETIRED 2026-06-11 — Roman: the
// player-tracking distortion "wasn't working"; only the mode-driven aberration stays.)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = off. ~0.0015-0.004 reads as a tasteful split at 480px internal width.
uniform float aberration = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Chromatic aberration: split R/B along the vector from screen center.
	if (aberration > 0.0001) {
		vec2 ca = (uv - vec2(0.5)) * aberration;
		float r = texture(screen_tex, uv + ca).r;
		float g = texture(screen_tex, uv).g;
		float b = texture(screen_tex, uv - ca).b;
		COLOR = vec4(r, g, b, 1.0);
	} else {
		COLOR = texture(screen_tex, uv);
	}
}
