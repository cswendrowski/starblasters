// Hexagon Shield — procedural hex-grid bubble, written for Starblaster
// (2026-06-10) after evaluating https://godotshaders.com/shader/hexagon-shield/
// (CC0, "Pan"). That shader needs an external repeating black/white hex
// texture and is visual-shader-generated; this is a clean reimplementation of
// the same idea (spherical-warped scrolling hex grid + rim) with NO texture,
// plus the `alpha` / `hit_strength` uniforms the existing sci_fi_shield
// drivers tween — so player.gd's _setup_shield_ring() and ShieldComponent can
// adopt it by swapping the preload path only.
shader_type canvas_item;
render_mode blend_add;

uniform vec4 shield_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform vec4 hit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0..1 alpha multiplier driven from GDScript (fades in on regen, out on depletion)
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Hit-pulse: 0..1, decayed by tween. Ripple ring expanding outward + brightening.
uniform float hit_strength : hint_range(0.0, 1.0) = 0.0;

// Hex columns across the bubble.
uniform float cells : hint_range(2.0, 24.0) = 7.0;
// Grid scroll, cells/second — gives the field a live "energy" drift.
uniform vec2 scroll = vec2(0.08, 0.05);
// Hex line width as a fraction of cell radius.
uniform float line_width : hint_range(0.02, 0.45) = 0.12;
// Fresnel-ish rim: higher = lines only light up near the bubble edge.
uniform float rim_power : hint_range(0.5, 6.0) = 2.2;
// Faint interior wash so the dome reads enclosed.
uniform float fill_alpha : hint_range(0.0, 0.4) = 0.05;
// Per-cell brightness flicker (0 = steady grid).
uniform float flicker : hint_range(0.0, 1.0) = 0.35;
// Spherical UV warp strength: 0 = flat grid, 1 = full dome bulge.
uniform float dome : hint_range(0.0, 1.0) = 0.65;

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.73))), p.x);
}

// Standard hex tiling: xy = position within cell, zw = cell id.
vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.73);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = (dot(a, a) < dot(b, b)) ? a : b;
	vec2 id = uv - gv;
	return vec4(gv, id);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0; // 0 centre → 1 bubble edge

	if (d > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// Dome warp: stretch UVs outward like the surface of a sphere, so the
		// hex cells foreshorten toward the rim.
		float z = sqrt(max(1.0 - d * d, 0.0));
		vec2 warped = mix(uv, uv / max(z, 0.18), dome);
		vec2 guv = warped * cells + scroll * TIME;
		vec4 hc = hex_coords(guv);

		// 0 at a cell border, 0.5 at a cell centre.
		float edge = 0.5 - hex_dist(hc.xy);
		float line = smoothstep(line_width, 0.0, edge);

		// Per-cell shimmer.
		float fl = hash21(hc.zw);
		float cell_glow = 0.5 + 0.5 * sin(TIME * 2.0 + fl * 6.2832);
		line *= mix(1.0, cell_glow, flicker);

		// Rim: lines brighten toward the bubble edge, plus a boundary ring.
		float rim = pow(d, rim_power);
		float boundary = smoothstep(0.82, 0.97, d) * (1.0 - smoothstep(0.97, 1.0, d));

		// Hit ripple expanding from the centre as hit_strength decays 1 → 0,
		// lighting whole hexes as it crosses them.
		float pulse_r = 1.0 - hit_strength;
		float ripple = (1.0 - smoothstep(0.0, 0.3, abs(d - pulse_r))) * hit_strength;

		float intensity = line * (0.25 + 0.75 * rim) + boundary * 0.9 + fill_alpha * (1.0 - rim * 0.5);
		vec3 col = shield_color.rgb;
		col = mix(col, hit_color.rgb, clamp(ripple, 0.0, 1.0) * 0.8);
		intensity += ripple * (0.35 + line);

		COLOR = vec4(col, clamp(intensity, 0.0, 1.0) * shield_color.a * alpha);
	}
}
