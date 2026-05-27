// Sapper drain beam — scrolling energy pulse from player end toward sapper.
// Applied as a ShaderMaterial on the outer Line2D.
// UV.x = 0 at sapper origin, 1 at player end.
// Scroll direction: +x over time so pulses travel 1→0 (player → sapper).
shader_type canvas_item;
render_mode blend_mix;

// Base teal beam color.
uniform vec4 beam_color : source_color = vec4(0.15, 0.95, 0.88, 1.0);

// Scroll speed in UV units per second.
uniform float scroll_speed : hint_range(0.0, 16.0) = 2.5;

// Number of bright pulse bands visible along the full beam length at once.
// 2.0 = two bright blobs traveling toward the sapper.
uniform float band_count : hint_range(0.5, 8.0) = 2.0;

// 0 = beam dims to near-black at trough; 1 = beam stays at full teal.
// 0.25 gives bold dark gaps between glowing blobs.
uniform float trough_brightness : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	// UV.x: 0=sapper end, 1=player end.
	// Adding TIME*speed to UV.x moves the pattern in the +x direction,
	// so each band travels from 1 (player) toward 0 (sapper).
	float phase = UV.x * band_count * TAU + TIME * scroll_speed * TAU;
	// sin goes -1..1 → remap to 0..1
	float wave = 0.5 + 0.5 * sin(phase);
	// Sharp pulse: raise wave to a power so the bright peaks are narrow blobs.
	float pulse = pow(wave, 3.0);
	float brightness = mix(trough_brightness, 1.5, pulse);
	float a = beam_color.a * COLOR.a;
	COLOR = vec4(clamp(beam_color.rgb * brightness, vec3(0.0), vec3(1.0)), a);
}
