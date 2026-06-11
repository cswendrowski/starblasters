shader_type canvas_item;
render_mode blend_add;

// On-sprite lightning (adapted from the Electric Ball shader, godotshaders.com — CC0) for enemies
// hit by the EM Torpedo: crackling electric filaments confined to the hull SILHOUETTE. This overlay
// node copies the enemy's current frame, so TEXTURE.a is the hull mask; the node's modulate alpha
// (COLOR.a) drives the fade-out. Additive, tinted blue-white. Roman 2026-06-10.
uniform sampler2D noise : repeat_enable;
uniform sampler2D noise2 : repeat_enable;
uniform float brightness = 1.9;
uniform float time_scale = 1.7;
uniform vec4 arc_color : source_color = vec4(0.62, 0.85, 1.0, 1.0);

void fragment() {
	// Hull mask — single tap, no neighbour sampling, so it reads the displayed hframe cleanly.
	float mask = texture(TEXTURE, UV).a;
	float time = TIME * time_scale;
	// Two scrolling noises beat together into thin moving bright lines (the crackle).
	float n1 = texture(noise, UV * 3.0 + vec2(time * 0.7, -time * 0.3)).r;
	float n2 = texture(noise2, UV * 2.4 + vec2(time * 0.4, time * 0.6)).r;
	float v = n1 * n2 + 0.4 * abs(n1 - n2);
	float arc = smoothstep(0.60, 0.92, v);
	// COLOR.a = the overlay node's modulate alpha (the fade). mask confines it to the hull.
	COLOR = arc_color * (arc * brightness) * mask * COLOR.a;
}
