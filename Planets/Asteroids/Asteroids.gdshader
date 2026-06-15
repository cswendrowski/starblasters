shader_type canvas_item;
render_mode blend_mix;

uniform float pixels : hint_range(10,100);
uniform float rotation : hint_range(0.0, 6.28) = 1.0;
uniform vec2 light_origin = vec2(0.39, 0.39);
uniform float time_speed : hint_range(0.0, 1.0) = 0.2;
uniform vec4[3] colors : source_color;
uniform float size = 50.0;
uniform int octaves : hint_range(0, 20, 1);
uniform float seed: hint_range(1, 10);
uniform bool should_dither = true;
// Roundness (Roman 2026-06-11): blends the SILHOUETTE noise toward its mean so the
// edge trends circular. 0 = original jagged shape (default — background rocks keep it);
// hazard rocks set ~0.4. Interior shading detail is unaffected.
uniform float roundness : hint_range(0.0, 1.0) = 0.0;
// 1-pixel black outline around the asteroid silhouette (Roman, 2026-05-24:
// "asteroids didn't pick up the pixel outline shader given"). Sampled at
// the same pixel grid as the body so the outline is exactly one pixel
// thick on the final 480x270 viewport.
uniform bool draw_outline = true;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float rand(vec2 coord) {
	return fract(sin(dot(coord.xy ,vec2(12.9898,78.233))) * 15.5453 * seed);
}

float noise(vec2 coord){
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));

	vec2 cubic = f * f * (3.0 - 2.0 * f);

	return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

float fbm(vec2 coord){
	float value = 0.0;
	float scale = 0.5;

	for(int i = 0; i < octaves ; i++){
		value += noise(coord) * scale;
		coord *= 2.0;
		scale *= 0.5;
	}
	return value;
}

bool dither(vec2 uv1, vec2 uv2) {
	return mod(uv1.x+uv2.y,2.0/pixels) <= 1.0 / pixels;
}

vec2 rotate(vec2 coord, float angle){
	coord -= 0.5;
	coord *= mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)));
	return coord + 0.5;
}

// by Leukbaars from https://www.shadertoy.com/view/4tK3zR
float circleNoise(vec2 uv) {
    float uv_y = floor(uv.y);
    uv.x += uv_y*.31;
    vec2 f = fract(uv);
	float h = rand(vec2(floor(uv.x),floor(uv_y)));
    float m = (length(f-0.25-(h*0.5)));
    float r = h*0.25;
    return m = smoothstep(r-.10*r,r,m);
}

float crater(vec2 uv) {
	float c = 1.0;
	for (int i = 0; i < 2; i++) {
		c *= circleNoise((uv * size) + (float(i+1)+10.));
	}
	return 1.0 - c;
}

// Reproduce just the silhouette test (n_step) at an arbitrary UV. Used
// by the outline pass to detect "outside this pixel, inside a neighbor."
// MUST apply the same `roundness` blend the body's n_step uses (fragment(): n_edge =
// mix(n, 0.5, roundness)) — otherwise the outline traces the RAW jagged silhouette while
// the body draws the ROUNDED one, so the ring mismatches the edge (the inconsistent-outline
// regression introduced when roundness was added 2026-06-11). Fix 2026-06-14.
float silhouette_at(vec2 base_uv) {
	vec2 uv_s = floor(base_uv * pixels) / pixels;
	float d_s = distance(uv_s, vec2(0.5));
	vec2 uv_r = rotate(uv_s, rotation);
	float n_s = fbm(uv_r * size);
	float n_edge = mix(n_s, 0.5, roundness);
	return step(0.2, n_edge - d_s);
}

void fragment() {
	//pixelize uv
	vec2 uv = floor(UV*pixels)/pixels;
	
	// we use this val later to interpolate between shades
	bool dith = dither(uv, UV);
	
	// distance from center
	float d = distance(uv, vec2(0.5));
	
	// optional rotation, do this after the dither or the dither will look very messed up
	uv = rotate(uv, rotation);
	
	// two noise values with one slightly offset according to light source, to create shadows later
	float n = fbm(uv * size);
	float n2 = fbm(uv * size + (rotate(light_origin, rotation)-0.5) * 0.5);
	
	// step noise values to determine where the edge of the asteroid is
	// step cutoff value depends on distance from center. Roundness blends the edge
	// noise toward its mean (0.5) so the silhouette trends circular (Roman 2026-06-11).
	float n_edge = mix(n, 0.5, roundness);
	float n_step = step(0.2, n_edge - d);
	float n2_step = step(0.2, n2 - d);
	
	// with this val we can determine where the shadows should be
	float noise_rel = (n2_step + n2) - (n_step + n);
	
	// two crater values, again one extra for the shadows
	float c1 = crater(uv );
	float c2 = crater(uv + (light_origin-0.5)*0.03);

	// now we just assign colors depending on noise values and crater values
	// base
	vec4 col = colors[1];
	
	// noise
	if (noise_rel < -0.06 || (noise_rel < -0.04 && (dith || !should_dither))) {
		col = colors[0];
	}
	if (noise_rel > 0.05 || (noise_rel > 0.03 && (dith || !should_dither))) {
		col = colors[2];
	}
	
	// crater
	if (c1 > 0.4)  {
		col = colors[1];
	}
	if (c2<c1) {
		col = colors[2];
	}
	
	COLOR = vec4(col.rgb, n_step * col.a);

	// Outline pass: if this pixel is outside the silhouette but any of
	// the 4-neighbor cells is inside, write outline_color. Sampled at
	// 1/pixels offsets so the band is exactly one pixelized cell thick.
	if (draw_outline && n_step < 0.5) {
		float step_px = 1.0 / pixels;
		float neighbor = 0.0;
		neighbor = max(neighbor, silhouette_at(UV + vec2( step_px, 0.0)));
		neighbor = max(neighbor, silhouette_at(UV + vec2(-step_px, 0.0)));
		neighbor = max(neighbor, silhouette_at(UV + vec2(0.0,  step_px)));
		neighbor = max(neighbor, silhouette_at(UV + vec2(0.0, -step_px)));
		if (neighbor > 0.5) {
			COLOR = outline_color;
		}
	}
}
