shader_type canvas_item;

// Procedural twinkling starfield. Stars are placed pseudo-randomly per
// cell of a UV grid so there's no visible tiling repetition.
// Scrolls downward over time to add motion to the void.

uniform float density : hint_range(4.0, 80.0) = 40.0;
uniform float scroll_speed : hint_range(0.0, 200.0) = 8.0;
uniform float twinkle_speed : hint_range(0.0, 4.0) = 0.6;
uniform float star_threshold : hint_range(0.80, 0.99) = 0.93;
uniform vec4 star_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(0.7, 0.85, 1.0, 1.0);
// Per-layer offset so multiple instances (parallax) get different patterns
uniform vec2 seed_offset = vec2(0.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Stretch UV by density, scroll vertically by TIME, offset per layer
	vec2 uv = UV * vec2(density, density * 1.25) + seed_offset;
	uv.y -= TIME * scroll_speed * 0.01;

	vec2 cell = floor(uv);
	vec2 local = fract(uv) - 0.5;

	float n = hash21(cell);
	float visible = step(star_threshold, n);

	// Random offset inside the cell so stars don't sit on a grid
	vec2 jitter = vec2(hash21(cell + 7.13), hash21(cell + 19.71)) - 0.5;
	float d = length(local - jitter * 0.4);

	float radius = mix(0.02, 0.10, hash21(cell + 3.14));
	float dot_sd = smoothstep(radius, 0.0, d);

	// Twinkle: each star's own phase
	float phase = n * 6.2831853;
	float twinkle = 0.55 + 0.45 * sin(TIME * twinkle_speed + phase);

	float brightness = visible * dot_sd * twinkle;
	vec3 col = mix(tint.rgb, star_color.rgb, hash21(cell + 11.0));
	COLOR = vec4(col, brightness);
}
