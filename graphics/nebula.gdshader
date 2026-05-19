// Custom soft nebula. Multi-octave FBM with smooth alpha falloff and
// optional pixelation for retro feel. Replaces the speckled Deep-Fold
// Nebulae shader which read as noise rather than clouds in our viewport.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float scale : hint_range(0.2, 8.0) = 2.5;
uniform int octaves : hint_range(1, 8) = 5;
uniform float seed : hint_range(0.0, 100.0) = 1.0;
uniform sampler2D colorscheme;
uniform float drift_speed : hint_range(0.0, 0.5) = 0.004;
// Caps the nebula's overall opacity so it stays in the background.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.35;
// Higher density = nebula fills more of the screen; lower = wispy islands.
uniform float density : hint_range(0.0, 2.0) = 0.9;
// Sharpness of cloud edges. 0 = very soft, 1 = harder edges.
uniform float edge_sharpness : hint_range(0.0, 1.0) = 0.4;
// Pixelation grid size. 0 = no pixelation (smooth); larger = chunkier retro.
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
		p *= 2.03;  // non-integer to avoid pattern alignment
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Optional pixelation: snap UV to a grid before sampling
	vec2 uv = UV;
	if (pixels > 1.0) {
		uv = floor(uv * pixels) / pixels;
	}
	// Drift the noise sampling space, not the vignette
	vec2 nuv = uv;
	nuv.y -= TIME * drift_speed;
	nuv *= uv_correct * scale;
	// Two noise layers — primary cloud + smaller-scale dust breaks up patterns
	float n_cloud = fbm(nuv, octaves);
	float n_dust  = fbm(nuv * 2.7 + vec2(11.3, 7.1), max(octaves - 2, 1));
	float v = n_cloud * 0.7 + n_dust * 0.3;
	// Density shifts the threshold; smoothstep gives soft edges
	float lo = clamp(1.0 - density * 0.5, 0.0, 1.0);
	float hi = clamp(lo + (1.0 - edge_sharpness) * 0.6 + 0.05, 0.0, 1.0);
	float t = smoothstep(lo, hi, v);
	// Sample colorscheme texture using the noise value for palette mapping
	vec3 col = texture(colorscheme, vec2(clamp(v, 0.0, 1.0), 0.5)).rgb;
	COLOR = vec4(col, t * max_alpha);
}
