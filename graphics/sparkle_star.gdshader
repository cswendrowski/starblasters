// 2D Sparkling Star Effect v2.x — CC0 (https://godotshaders.com/shader/2d-sparkling-star-effect-ver-2-0/).
// Reimport for Starblaster (2026-07-09) as an ALTERNATE glow to pixel_halo_glow: a rotating diffraction-
// spike twinkle. Deviations from the source, both intentional: (1) render_mode blend_add so it reads as
// an ADDITIVE glow over a background instead of darkening it; (2) the source's declared-but-unused
// `cut_magnitude` uniform is now wired into the intensity cut (was a hard-coded 0.05). Single `color`
// (no gradient). NOTE: uses SCREEN_PIXEL_SIZE, so the spike thickness is viewport-resolution relative.
shader_type canvas_item;
render_mode blend_add;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float scale : hint_range(0.1, 10000.0, 0.1) = 7500.0;
uniform float circle_ratio : hint_range(0.0, 100.0, 0.1) = 0.0;
uniform float decay_magnitude : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float cut_magnitude : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float rotate_speed : hint_range(-1000.0, 1000.0, 0.01) = 1.0;
uniform float time_speed : hint_range(-1000.0, 1000.0, 0.01) = 1.0;
uniform float frequency_base : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float frequency_disturbance_scale : hint_range(0.0, 10.0, 0.01) = 0.0;
uniform bool stop_shine = false;

float onedx(float x) {
	if (x + 1.0 - 1.0 == 0.0) {
		return 1.0;
	} else {
		return 1.0 / x;
	}
}

float onedx2(float x) {
	return onedx(x) * onedx(x);
}

float getBetaW(float x, float f, float size) {
	return size * x * 3.1415926 / f;
}

float getBetaH(float y, float f, float size) {
	return size * y * 3.1415926 / f;
}

float getI(vec2 uv, float f, vec2 SIZE) {
	return onedx2(getBetaW(uv.x, f, SIZE.x)) * onedx2(getBetaH(uv.y, f, SIZE.y));
}

vec2 rotate(vec2 uv, float addtheta) {
	float theta = atan(uv.y / uv.x) + addtheta;
	float r = sqrt(uv.x * uv.x + uv.y * uv.y);
	vec2 ruv;
	ruv.x = r * cos(theta);
	ruv.y = r * sin(theta);
	return ruv;
}

void fragment() {
	vec2 st = rotate((UV - 0.5) * scale, TIME * rotate_speed);
	float r = sqrt(st.x * st.x + st.y * st.y);
	st = st * pow(r, circle_ratio);
	float time = TIME * time_speed;
	float f = frequency_base + frequency_disturbance_scale * (3.0 * sin(time) + 2.0 * cos(time * 4.0) + 6.0 * sin(time * 2.0) + 1.0 * sin(time * 3.0));
	float L = distance(UV, st);
	float M = exp(-L * L * decay_magnitude * decay_magnitude / scale);
	M = M < cut_magnitude ? 0.0 : M;
	f = stop_shine ? frequency_base : f;
	COLOR = vec4(min(vec3(getI(st, f, SCREEN_PIXEL_SIZE)) * M, 1.0), 1.0) * color;
}
