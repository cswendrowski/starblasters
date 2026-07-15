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

// TIME-driven swirl — evolves the domain-warp field IN PLACE (the two warp samples drift along
// different vectors), so the filaments curl/churn over time instead of only translating with the
// scroll. 0 = static shape (legacy, live default). Keep low — it's a backdrop. (Roman 2026-06-12)
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.0;

// Wisp layer — narrow-band threshold of a higher-frequency FBM, sells the
// stringy filaments you see in Hubble photos.
uniform float wisp_strength : hint_range(0.0, 1.0) = 0.35;

uniform float pixels : hint_range(0.0, 800.0) = 200.0;
uniform vec2 uv_correct = vec2(1.0);
// Host rect size in px — lets the pixelation snap to SQUARE, native-pixel-aligned cells (the old
// uniform-UV snap gave non-square, off-grid cells on the 480×270 rect = glitchy pixelation).
uniform vec2 rect_size = vec2(480.0, 270.0);

// Ship drop shadows (Planet Flyover lab) — `shadow_mask` is a viewport texture holding
// every caster's silhouette; darkens rgb only, density-gated so shadow lives only on the
// dense cloud body. strength 0 = off (the default: other users of this shader unaffected).
uniform sampler2D shadow_mask : filter_nearest;
uniform float shadow_strength = 0.0;

// Integer hash — precision-robust at large/negative coords. The old fract(sin(...)) hash banded once
// scale × warp × the FBM octave multiplier pushed sample coords into the thousands (sin loses float32
// precision there), which read as glitchy blocky patches. (Roman 2026-06-12)
uint _ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float hash(vec2 p) {
	ivec2 ip = ivec2(floor(p));
	uint h = _ihash(uint(ip.x) * 0x9e3779b9u + uint(ip.y));
	h ^= uint(seed * 4096.0);
	return float(_ihash(h)) * (1.0 / 4294967296.0);
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
	// Pixelation first — snap UV to SQUARE cells aligned to the native pixel grid. `pixels` = cells
	// across the WIDTH; we derive a whole-native-px chunk and apply the SAME chunk on both axes, so
	// cells stay square on the non-square rect and their edges land on native pixels (the old uniform
	// `floor(UV*pixels)` gave 2.4×1.35px off-grid cells = the glitchy/weird pixelation).
	vec2 uv = UV;
	if (pixels > 1.0) {
		float chunk = max(1.0, round(rect_size.x / pixels));   // native px per square cell
		vec2 px = floor(UV * rect_size);
		px = floor(px / chunk) * chunk;
		uv = px / rect_size;
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
	// Animate the two warp samples along DIFFERENT vectors so the displacement field rotates/churns
	// at each point (curling filaments) rather than rigidly translating. ts=0 → static (legacy).
	float ts = TIME * swirl_speed;
	vec2 q = vec2(
		fbm(nuv * warp_scale + vec2(ts * 0.12, ts * 0.10), warp_oct),
		fbm(nuv * warp_scale + vec2(5.2, 1.3) + vec2(-ts * 0.09, ts * 0.11), warp_oct)
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
		float n_wisp = fbm(wuv * 3.5 + vec2(2.8, 9.7) + vec2(ts * 0.15, -ts * 0.08), max(octaves - 1, 3));
		float wisp_band = smoothstep(0.55, 0.7, n_wisp) - smoothstep(0.7, 0.85, n_wisp);
		t = clamp(t + wisp_band * wisp_strength, 0.0, 1.0);
	}

	// Palette mapping — noise value drives the gradient lookup.
	vec3 col = texture(colorscheme, vec2(clamp(v, 0.0, 1.0), 0.5)).rgb;

	COLOR = vec4(col, t * max_alpha * opacity);

	if (shadow_strength > 0.0) {
		// Density gate on t (pre-max_alpha density): shadow only on the dense body,
		// exactly zero on wisps and clear sky.
		float sm = texture(shadow_mask, uv).a;
		COLOR.rgb *= 1.0 - sm * shadow_strength * smoothstep(0.45, 0.85, t);
	}
}
