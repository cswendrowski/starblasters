// Nebula 2 — extends graphics/nebula.gdshader with domain warping (curling
// filament look that real nebulae have) + an external scroll_offset uniform
// (gameplay-driven infinite flight, no seams since the noise is procedural).
// Master `opacity` knob multiplies the final alpha so designers can fade the
// nebula in/out without touching density. Pixelation is preserved so the
// pixel-art aesthetic survives the extra detail.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float scale : hint_range(0.2, 8.0) = 2.5;
uniform int octaves : hint_range(1, 8) = 5;
uniform float seed : hint_range(0.0, 100.0) = 1.0;
uniform sampler2D colorscheme;

// External scroll offset — drive from GD with e.g. mat.set_shader_parameter("scroll_offset", v).
// Combines with drift_speed for fallback motion when nothing is driving it.
uniform vec2 scroll_offset = vec2(0.0);
uniform float drift_speed : hint_range(0.0, 0.5) = 0.004;

// Master opacity multiplier — separate knob from the threshold-based max_alpha.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.7;

uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform float edge_sharpness : hint_range(0.0, 1.0) = 0.4;

// Domain-warp knobs. warp_strength = 0 reduces to the old shader exactly.
uniform float warp_strength : hint_range(0.0, 4.0) = 1.4;
uniform float warp_scale : hint_range(0.2, 4.0) = 1.1;

// Wisp layer — narrow-band threshold of a higher-frequency FBM, sells the
// stringy filaments you see in Hubble photos.
uniform float wisp_strength : hint_range(0.0, 1.0) = 0.35;

uniform float pixels : hint_range(0.0, 800.0) = 200.0;
uniform vec2 uv_correct = vec2(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 8; i++) {
		if (i >= oct) break;
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Pixelation first — snap UV to the grid so every later sample reads
	// from the same cell, preserving the chunky aesthetic.
	vec2 uv = UV;
	if (pixels > 1.0) {
		uv = floor(uv * pixels) / pixels;
	}

	// External scroll (gameplay-driven) + the legacy time drift on Y.
	vec2 nuv = uv;
	nuv -= scroll_offset;
	nuv.y -= TIME * drift_speed;
	nuv *= uv_correct * scale;

	// Domain warp: sample a low-octave FBM twice (with an offset) to build a
	// vec2 perturbation, then warp the main FBM input by it. Inigo Quilez's
	// recipe — gives nebulae the swirling/filament look real photos have.
	int warp_oct = max(octaves - 2, 2);
	vec2 q = vec2(
		fbm(nuv * warp_scale, warp_oct),
		fbm(nuv * warp_scale + vec2(5.2, 1.3), warp_oct)
	);
	vec2 wuv = nuv + warp_strength * (q - 0.5);

	// Primary cloud + smaller dust layer (carried over from the original).
	float n_cloud = fbm(wuv, octaves);
	float n_dust  = fbm(wuv * 2.7 + vec2(11.3, 7.1), max(octaves - 2, 1));
	float v = n_cloud * 0.7 + n_dust * 0.3;

	// Density-aware threshold for soft cloud edges.
	float lo = clamp(1.0 - density * 0.5, 0.0, 1.0);
	float hi = clamp(lo + (1.0 - edge_sharpness) * 0.6 + 0.05, 0.0, 1.0);
	float t = smoothstep(lo, hi, v);

	// Wisp pass — narrow-band peak of a higher-octave FBM, adds filament
	// streaks on top of the soft body. Cheap (one extra FBM call).
	if (wisp_strength > 0.0) {
		float n_wisp = fbm(wuv * 3.5 + vec2(2.8, 9.7), max(octaves - 1, 3));
		float wisp_band = smoothstep(0.55, 0.7, n_wisp) - smoothstep(0.7, 0.85, n_wisp);
		t = clamp(t + wisp_band * wisp_strength, 0.0, 1.0);
	}

	// Palette mapping — noise value drives the gradient lookup.
	vec3 col = texture(colorscheme, vec2(clamp(v, 0.0, 1.0), 0.5)).rgb;

	COLOR = vec4(col, t * max_alpha * opacity);
}
