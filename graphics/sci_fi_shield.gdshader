// Sci-Fi Shield - 2D canvas_item adaptation inspired by https://godotshaders.com/shader/sci-fi-shield/ (page 404 at fetch time; ring + hit-pulse concept reproduced).
shader_type canvas_item;
render_mode blend_add;

uniform vec4 shield_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform vec4 hit_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0..1 alpha multiplier driven from GDScript (fades in on regen, out on depletion)
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

// Ring geometry in UV space (0.5 = centre, 0.5 = outer edge)
uniform float ring_radius : hint_range(0.0, 0.5) = 0.42;
uniform float ring_width  : hint_range(0.001, 0.5) = 0.06;

// Fresnel-like falloff sharpness (higher = thinner glow)
uniform float edge_sharpness : hint_range(0.5, 8.0) = 2.0;

// Hit-pulse: 0..1, decayed by tween. Drives a ripple ring expanding outward + brightening.
uniform float hit_strength : hint_range(0.0, 1.0) = 0.0;

// Subtle animated shimmer
uniform float shimmer_speed : hint_range(0.0, 8.0) = 2.5;
uniform float shimmer_amount : hint_range(0.0, 1.0) = 0.18;

float ring_mask(float d, float r, float w, float sharp) {
	// Smooth band centered on r with half-width w
	float band = 1.0 - smoothstep(0.0, w, abs(d - r));
	return pow(band, sharp);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);

	// Discard pixels well outside the ring to keep things cheap and clean
	if (d > 0.5) {
		COLOR = vec4(0.0);
	} else {
		// Base ring
		float base = ring_mask(d, ring_radius, ring_width, edge_sharpness);

		// Animated shimmer along the ring (angle-based)
		float ang = atan(uv.y, uv.x);
		float shimmer = 0.5 + 0.5 * sin(ang * 6.0 + TIME * shimmer_speed);
		base *= mix(1.0 - shimmer_amount, 1.0 + shimmer_amount, shimmer);

		// Hit pulse: expanding ripple, plus a flash that broadens the ring
		float pulse_r = mix(ring_radius, 0.5, 1.0 - hit_strength); // expands outward as strength decays
		float ripple = ring_mask(d, pulse_r, ring_width * (0.5 + hit_strength * 1.5), edge_sharpness * 0.75);
		ripple *= hit_strength;

		// Inner soft fill (very faint) so the dome reads as enclosed
		float fill = (1.0 - smoothstep(ring_radius - 0.02, ring_radius + ring_width, d)) * 0.08;

		vec3 col = shield_color.rgb * (base + fill);
		col += hit_color.rgb * ripple * 1.2;

		float a = clamp(base + ripple + fill * 0.5, 0.0, 1.0);
		a *= shield_color.a * alpha;

		COLOR = vec4(col, a);
	}
}
