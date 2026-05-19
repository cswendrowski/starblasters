shader_type canvas_item;

// Screen-space bloom — samples SCREEN_TEXTURE around each fragment in a
// ring pattern, picks up pixels above `threshold`, and renders an additive
// glow that fades with distance. Stick this on a CanvasItem overlay placed
// over the planet; the planet's own disc colors become the bloom source so
// halo color matches the disc by construction (no palette plumbing needed).
//
// Author: Starblaster, derived from the godotshaders.com bloom recipe.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Brightness threshold below which a pixel doesn't contribute to bloom.
uniform float threshold : hint_range(0.0, 1.0) = 0.45;
// Additive multiplier on the bloomed result.
uniform float intensity : hint_range(0.0, 4.0) = 1.4;
// Sample ring radius as a fraction of the screen. ~0.05 = 5% of screen.
uniform float radius : hint_range(0.0, 0.2) = 0.06;
// Number of angular samples (per ring).
uniform int angle_samples : hint_range(4, 32) = 12;
// Number of radial rings.
uniform int radial_samples : hint_range(1, 8) = 4;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Account for non-square viewport so the ring stays circular.
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = screen_size.y / screen_size.x;
	vec3 bloom = vec3(0.0);
	float total = 0.0;
	float pi2 = 6.28318530718;
	for (int i = 0; i < angle_samples; i++) {
		float a = float(i) / float(angle_samples) * pi2;
		vec2 dir = vec2(cos(a), sin(a) * aspect);
		for (int r = 1; r <= radial_samples; r++) {
			float t = float(r) / float(radial_samples);
			vec2 off = dir * radius * t;
			vec3 s = texture(screen_tex, uv + off).rgb;
			float lum = max(s.r, max(s.g, s.b));
			// Soft threshold: full weight above `threshold`, fades below.
			float w = smoothstep(threshold * 0.5, threshold, lum);
			// Distance falloff so outer ring contributes less.
			w *= 1.0 - t;
			bloom += s * w;
			total += w;
		}
	}
	if (total > 0.0001) {
		bloom /= total;
	}
	COLOR = vec4(bloom * intensity, 1.0);
}
