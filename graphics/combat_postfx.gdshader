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

// Ripple: center in SCREEN UV, current radius (UV units), ring half-width, and a
// strength the controller decays to 0. amount 0 = no ripple.
uniform vec2  ripple_center = vec2(0.5, 0.5);
uniform float ripple_radius = 0.0;
uniform float ripple_width  = 0.06;
uniform float ripple_strength = 0.0;

// D1 heat-haze: a soft shimmer disc that tracks the player's exhaust (just behind
// the ship). center in SCREEN UV; radius in UV; strength 0 = off.
uniform vec2  haze_center = vec2(0.5, 0.5);
uniform float haze_radius = 0.10;
uniform float haze_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 off = vec2(0.0);

	// --- radial ripple displacement ---
	if (ripple_strength > 0.001) {
		vec2 d = uv - ripple_center;
		// Aspect-correct the distance so the ring stays round on a wide rect.
		float dist = length(d);
		// A single sine lobe centered on the expanding radius; zero outside the ring.
		float band = 1.0 - smoothstep(0.0, ripple_width, abs(dist - ripple_radius));
		float push = sin((dist - ripple_radius) / max(ripple_width, 0.001) * 3.14159) * band;
		vec2 dir = (dist > 0.0001) ? d / dist : vec2(0.0);
		off += dir * push * ripple_strength * 0.03;
	}

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
