// Procedural cloud/haze field — a flat, vertically-scrolling, seamlessly-looping fbm
// blob field. Originally drafted as a "planet ground" (from PixelPlanets' land-mass fbm
// with spherify() removed) but it reads as a soft blob field with no discernible surface
// features, so it's PARKED here as a candidate procedural cloud layer (an alternative to
// nebula2.gdshader) — NOT wired into anything yet.
//
// SEAMLESS LOOP: rand() tiles the lattice at period vec2(2,1)*round(size), so the fbm is
// periodic with period round(size) along Y. The driver wraps the `scroll` uniform at
// round(size) (keep `size` integer) so the vertical scroll has no seam frame.
shader_type canvas_item;
render_mode blend_mix;

// Pixelation — square, native-pixel-aligned cells. `pixels` = cells across the WIDTH. 0 disables.
uniform float pixels : hint_range(0.0, 800.0) = 160.0;
uniform vec2 rect_size = vec2(480.0, 270.0);

// Feature density (cells across the screen), decoupled from `size` (the tiling period).
uniform float feature_scale : hint_range(2.0, 40.0) = 8.0;
uniform float size = 32.0;   // tiling period — MUST be integer for a seamless loop
uniform int OCTAVES : hint_range(1, 12) = 5;
uniform float seed : hint_range(1.0, 10.0) = 1.0;

// Vertical scroll offset (noise-cell units). Advanced + wrapped at round(size) in GD.
uniform float scroll = 0.0;

uniform vec2 light_dir = vec2(0.35, 0.35);
uniform vec4[4] colors : source_color;
uniform float relief : hint_range(0.0, 1.0) = 0.22;


float rand(vec2 coord) {
	coord = mod(coord, vec2(2.0, 1.0) * round(size));
	return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 15.5453 * seed);
}

float noise(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));
	vec2 cubic = f * f * (3.0 - 2.0 * f);
	return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

float fbm(vec2 coord) {
	float value = 0.0;
	float scl = 0.5;
	for (int i = 0; i < OCTAVES; i++) {
		value += noise(coord) * scl;
		coord *= 2.0;
		scl *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	if (pixels > 1.0) {
		float chunk = max(1.0, round(rect_size.x / pixels));
		vec2 px = floor(UV * rect_size);
		px = floor(px / chunk) * chunk;
		uv = px / rect_size;
	}

	float aspect = rect_size.x / rect_size.y;
	vec2 coord = vec2(uv.x * aspect, uv.y) * feature_scale;
	coord.y -= scroll;

	float fbm1 = fbm(coord);
	float fbm2 = fbm(coord - light_dir * fbm1);
	float fbm3 = fbm(coord - light_dir * 1.5 * fbm1);
	float fbm4 = fbm(coord - light_dir * 2.0 * fbm1);

	vec4 col = colors[3];
	if (fbm4 < fbm1) { col = colors[2]; }
	if (fbm3 < fbm1) { col = colors[1]; }
	if (fbm2 < fbm1) { col = colors[0]; }

	float shade = 1.0 + (fbm1 - 0.5) * relief;
	COLOR = vec4(col.rgb * shade, col.a);
}
