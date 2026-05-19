shader_type canvas_item;
// Add the glow to whatever's underneath rather than mix-blending over it,
// so the disc + adjacent backdrop pixels gain brightness instead of being
// overwritten by a translucent ColorRect (Roman, 2026-05-17).
render_mode blend_add;

// Item-pulse-glow style halo. The original shader (godotshaders.com/shader/
// item-pulse-glow) outlines a sprite's alpha and adds a pulsing color glow.
// We don't have a sprite — the BlackHole is shader-rendered — so this
// variant draws the glow itself: a radial falloff from the quad center,
// tinted by `glow_color`, intensity-modulated by a sine pulse over time.
// Composited additively over the planet's own disc.

uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.9, 1.0);
// Radial falloff distance (0..0.5 = quad center to edge). Glow softens
// to zero past this.
uniform float glow_width : hint_range(0.0, 0.5) = 0.42;
// Inner radius below which glow is at full strength (avoids a hot spot at
// the exact quad center).
uniform float glow_inner : hint_range(0.0, 0.5) = 0.05;
// Sine pulse bounds — actual intensity oscillates between these.
uniform float pulse_min : hint_range(0.0, 2.0) = 0.55;
uniform float pulse_max : hint_range(0.0, 2.0) = 1.05;
// Pulse rate in radians/sec.
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.6;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	// Smooth falloff: full glow inside `glow_inner`, fading to 0 by
	// `glow_width`.
	float falloff = 1.0 - smoothstep(glow_inner, glow_width, dist);
	float pulse = pulse_min + (pulse_max - pulse_min) * 0.5 * (1.0 + sin(TIME * pulse_speed));
	float a = falloff * pulse * glow_color.a;
	COLOR = vec4(glow_color.rgb * a, a);
}
