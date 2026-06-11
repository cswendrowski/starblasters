shader_type canvas_item;

// Combat post-FX (Roman renderer-polish D, 2026-06-11). One screen-reading pass on
// a playfield-band rect that composites two Forward+-affordable sweeteners:
//   * chromatic aberration — R/B channels split outward, driven by `aberration`
//     (raised while an aggressive Shift-mode is engaged: hyper / phase dash).
//   * radial ripple — an expanding ring of UV displacement, pinged by big
//     explosions / boss slams (`ripple_strength` decays the controller toward 0).
// Band-limited by the host rect (X 132-348), so the HUD + glass gutters never warp.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = off. ~0.0015-0.004 reads as a tasteful split at 480px internal width.
uniform float aberration = 0.0;

// D1 heat-haze: a soft shimmer disc that tracks the player's exhaust (just behind
// the ship). center in SCREEN UV; radius in UV; strength 0 = off.
uniform vec2  haze_center = vec2(0.5, 0.5);
uniform float haze_radius = 0.10;
uniform float haze_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 off = vec2(0.0);

	// --- heat-haze shimmer behind the exhaust ---
	if (haze_strength > 0.001) {
		float hd = distance(uv, haze_center);
		float falloff = 1.0 - smoothstep(0.0, haze_radius, hd);
		// Rising vertical shimmer: wobble x by a couple stacked sines keyed off y+time.
		float w = sin(uv.y * 90.0 + TIME * 9.0) + 0.5 * sin(uv.y * 160.0 - TIME * 13.0);
		off.x += w * falloff * haze_strength * 0.0025;
	}

	// --- chromatic aberration (split along the vector from screen center) ---
	vec4 col;
	if (aberration > 0.0001) {
		vec2 cdir = uv - vec2(0.5);
		vec2 ca = cdir * aberration;
		float r = texture(screen_tex, uv + off + ca).r;
		float g = texture(screen_tex, uv + off).g;
		float b = texture(screen_tex, uv + off - ca).b;
		col = vec4(r, g, b, 1.0);
	} else {
		col = texture(screen_tex, uv + off);
	}
	COLOR = col;
}
