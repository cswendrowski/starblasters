// Cloud Layer — the parked V1 land-mass generator (proc_clouds.gdshader) repurposed as
// Roman intended: DITCH the blue/water bands, keep the white "terrain" as CLOUDS. The
// multi-fbm band ladder that used to pick 4 terrain colours now picks 4 opacity/
// brightness levels of ONE tintable cloud colour (wisp edge → dense bright core), and
// the kit's land_cutoff becomes the coverage gate (fbm below cutoff = clear sky).
// Scrolls seamlessly like the ground: same tiled-lattice rules, driver wraps `scroll`
// at 2×round(size) (all coeffs here are 1 or translations).
shader_type canvas_item;
render_mode blend_mix;

// Pixelation — square, native-pixel-aligned cells. `pixels` = cells across the WIDTH.
uniform float pixels : hint_range(0.0, 800.0) = 160.0;
uniform vec2 rect_size = vec2(480.0, 270.0);

uniform float feature_scale : hint_range(2.0, 40.0) = 5.0;
uniform float size = 32.0;   // tiling period — integer, shared with the ground
uniform int OCTAVES : hint_range(1, 12) = 5;
uniform float seed : hint_range(1.0, 10.0) = 1.0;

// Vertical scroll offset (noise-cell units). Advanced + wrapped at 2×round(size) in GD.
uniform float scroll = 0.0;

// The multi-fbm offset direction — shapes the band stacking (was light_dir/erosion).
uniform vec2 wind_dir = vec2(0.35, 0.35);

uniform vec4 cloud_color : source_color = vec4(1.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.55;   // higher = more sky covered
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// Ship drop shadows — `shadow_mask` is a viewport texture holding EVERY caster's
// silhouette (per-layer offset + scale baked into the mask sprites, so one sample serves
// any number of ships). Multiplies rgb only, and is gated by cloud DENSITY below so the
// shadow lives on the solid cloud body and fully vanishes off it. strength 0 = off.
uniform sampler2D shadow_mask : filter_nearest;
uniform float shadow_strength = 0.0;


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

	float f1 = fbm(coord);
	float f2 = fbm(coord - wind_dir * f1);
	float f3 = fbm(coord - wind_dir * 1.5 * f1);
	float f4 = fbm(coord - wind_dir * 2.0 * f1);

	// The land-mass band ladder → cloud density: wisp edge to dense over-bright core.
	float a = 0.30;
	float b = 0.85;
	if (f4 < f1) { a = 0.55; b = 0.92; }
	if (f3 < f1) { a = 0.80; b = 1.00; }
	if (f2 < f1) { a = 1.00; b = 1.08; }

	// Coverage gate — the kit's land_cutoff: below the threshold the sky is clear.
	float gate = step(1.0 - coverage * 0.8, f1);

	COLOR = vec4(cloud_color.rgb * b, gate * a * opacity * cloud_color.a);

	if (shadow_strength > 0.0) {
		// Density gate: only the dense bands (gate*a >= ~0.5) catch shadow — on wisps and
		// clear sky it is exactly zero, so the shadow never half-lingers off the cloud.
		float sm = texture(shadow_mask, uv).a;
		COLOR.rgb *= 1.0 - sm * shadow_strength * smoothstep(0.5, 0.95, gate * a);
	}
}
