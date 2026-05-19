// Hologram banner shader (canvas_item)
// Authored fresh for this project — the canonical Hologram Effect on
// godotshaders.com is a spatial shader and unsuitable for 2D UI use.
// Implements: scanlines, chromatic aberration, alpha jitter / flicker,
// vertical edge fade. Cyan/teal palette by default.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 holo_color : source_color = vec4(0.45, 1.0, 0.95, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_freq : hint_range(1.0, 400.0) = 90.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_scroll_speed : hint_range(-8.0, 8.0) = 1.2;
uniform float chromatic_offset : hint_range(0.0, 0.05) = 0.006;
uniform float jitter_amount : hint_range(0.0, 0.1) = 0.012;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.18;
uniform float flicker_speed : hint_range(0.0, 60.0) = 22.0;
uniform float edge_fade : hint_range(0.0, 0.5) = 0.12;
uniform float glow : hint_range(0.0, 3.0) = 1.4;

// HUD-mode extensions. All default to 0 / no-effect so the wave_banner that
// also uses this shader keeps its existing look.
uniform float damage_level : hint_range(0.0, 1.0) = 0.0;
uniform float disruption : hint_range(0.0, 4.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 damage_color : source_color = vec4(1.0, 0.25, 0.15, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 uv = UV + uv_offset;

	// Aggregate disruption: transient (env / damage flash) + sustained (low hull).
	// damage_level contributes 2x so a near-death HUD is permanently glitchy.
	float boost = 1.0 + disruption + damage_level * 2.0;

	// Horizontal jitter per scanline row (slices feel "transmitted").
	float row = floor(uv.y * 64.0);
	float jx = (hash(vec2(row, floor(TIME * 18.0))) - 0.5) * 2.0 * jitter_amount * boost;
	uv.x += jx;

	// Chromatic aberration: sample r/b channels offset, g centered.
	float a_r = texture(TEXTURE, uv + vec2(chromatic_offset, 0.0)).a;
	float a_g = texture(TEXTURE, uv).a;
	float a_b = texture(TEXTURE, uv - vec2(chromatic_offset, 0.0)).a;

	vec3 tint = holo_color.rgb;
	vec3 col = vec3(
		tint.r * a_r + tint.r * a_g * 0.5,
		tint.g * a_g,
		tint.b * a_b + tint.b * a_g * 0.5
	);
	col *= glow;

	float src_a = max(max(a_r, a_g), a_b);

	// Scanlines — chunky to match pixel-art look.
	float scan = 0.5 + 0.5 * sin((uv.y + TIME * scanline_scroll_speed * 0.01) * scanline_freq * 6.2831853);
	scan = mix(1.0, scan, scanline_strength);
	col *= scan;

	// Vertical edge fade (top + bottom) so the banner feels projected.
	float ef = smoothstep(0.0, edge_fade, uv.y) * smoothstep(0.0, edge_fade, 1.0 - uv.y);

	// Flicker — quantized so it pops.
	float fl = sin(TIME * flicker_speed) * 0.5 + 0.5;
	fl = floor(fl * 4.0) / 4.0;
	float eff_flicker = clamp(flicker_amount * boost, 0.0, 1.0);
	float flick = 1.0 - fl * eff_flicker;

	// Damage tint: bleed final color toward damage_color as hull drops.
	col = mix(col, damage_color.rgb * glow, damage_level);

	// Dissolve: kill alpha for rows whose hash falls below the dissolve
	// threshold. Uses the chunky scanline row band so pieces "fall away"
	// in slices that match the existing scanline look.
	float diss_mask = 1.0;
	if (dissolve > 0.0) {
		float drow = floor(uv.y * 32.0);
		float h = hash1(drow + floor(dissolve * 12.0) * 7.0);
		diss_mask = step(dissolve, h);
	}

	float out_a = src_a * alpha * ef * flick * diss_mask;
	COLOR = vec4(col, out_a);
}
