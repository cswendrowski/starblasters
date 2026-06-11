shader_type canvas_item;
render_mode blend_add;

// Electric ball (adapted from godfreyo's "Electric Ball" canvas_item shader, godotshaders.com —
// CC0). Drives the EM Torpedo's detonation ring: a polar-mapped sphere of noise-driven lightning
// rays radiating from the centre, tinted by the node's modulate COLOR. Used at native pixel scale
// on a white quad scaled to the burst radius. Roman 2026-06-10.
uniform sampler2D noise : repeat_enable;
uniform sampler2D noise2 : repeat_enable;
uniform float brightness = 2.5;
uniform float time_scale = 1.0;

void fragment() {
	vec2 cc_uv = UV - vec2(0.5);
	float angle = atan(cc_uv.y, cc_uv.x) / PI + 1.0;
	float p = sqrt(dot(cc_uv, cc_uv));
	vec2 puv = vec2(p, angle * 0.5);
	vec2 uv = puv * 2.0;
	float time = TIME * time_scale;
	vec4 old_colo = COLOR;
	COLOR = vec4(0.0);
	for (int i = 1; i <= 5; i++) {
		float intensive = 0.1 + 0.07 * float(i);
		vec2 offset = (texture(noise, vec2(time * 0.35 * (0.5 + fract(sin(float(i) * 55.0))), angle)).rg - vec2(0.5)) * intensive;
		vec2 uuv = uv + offset;
		float dist = abs(uuv.x - 0.5);
		float rand_speed = 0.2 + 0.05 * fract(cos(float(i) * 1144.0));
		float gone = smoothstep(0.1 + 0.05 * (float(i) - 0.5), 1.0, texture(noise2, uv + vec2(time * rand_speed)).s);
		COLOR += gone * old_colo / max(dist, 0.001) * 0.01 * texture(noise2, uuv + vec2(time)).s;
	}
	vec4 light = old_colo * smoothstep(1.0, -2.0, abs(uv.x - 0.5) * 2.0) * texture(noise2, uv).a;
	COLOR += light * brightness;
	// Fade the whole ball out past the quad's circle so the square edges never show.
	COLOR *= smoothstep(0.5, 0.34, p);
}
