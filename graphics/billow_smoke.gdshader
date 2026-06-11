// Shard Noise — procedural multi-octave billow.
//
// Source: https://godotshaders.com/shader/shard-noise/
// Original: @ENDESGA on Shadertoy (https://www.shadertoy.com/view/dlKyWw)
// Godot port: Zenryoku | License: CC0
//
// Adapted for Starblaster damage-smoke puffs (Roman/Cody 2026-05-18):
// "burning industrial / tech smoke from damaged components, billowy and
// dark." Each puff is a small ColorRect with this shader. The puff
// emitter animates scale + alpha over the puff's lifetime so the noise
// reads as a growing-then-dispersing cloud.

shader_type canvas_item;

uniform vec4 smoke_color : source_color = vec4(0.10, 0.10, 0.11, 1.0);
uniform float timescale : hint_range(0.0, 2.0) = 0.35;
uniform float h_scroll : hint_range(-2.0, 2.0) = 0.0;
uniform float v_scroll : hint_range(-2.0, 2.0) = -0.25;
uniform float entropy  : hint_range(0.0, 4.0) = 1.0;
uniform float sharpness : hint_range(0.5, 20.0) = 3.5;
// Radial alpha falloff — fades the puff out at its edge so it reads as a
// soft blob rather than a hard rectangle. 0 = sharp, 1 = aggressive fade.
uniform float edge_fade : hint_range(0.0, 1.0) = 0.7;
// Output alpha multiplier driven by the emitter's lifecycle (1 at birth,
// fades to 0 at death).
uniform float life_alpha : hint_range(0.0, 1.0) = 1.0;


vec3 hash(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	p = fract(sin(p) * 43758.5453123);
	return p;
}

float shard_noise(in vec3 p, in float _sharpness) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float v = 0.0;
	float t = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 io = ip + o;
				vec3 h = hash(io);
				vec3 r = fp - (o + h);
				float w = exp2(-TAU * dot(r, r));
				float s = _sharpness * dot(r, hash(io + vec3(11, 31, 47)) - 0.5);
				v += w * s * inversesqrt(1.0 + s * s);
				t += w;
			}
		}
	}
	return ((v / t) * 0.5) + 0.5;
}

void fragment() {
	vec3 uv = vec3(UV.x + TIME * timescale * h_scroll, UV.y + TIME * timescale * v_scroll, TIME * timescale * 0.5 * entropy);
	float n = (
		shard_noise(128.0 * uv, sharpness) * 0.03125 +
		shard_noise(32.0 * uv, sharpness) * 0.0625 +
		shard_noise(16.0 * uv, sharpness) * 0.125 +
		shard_noise(8.0 * uv, sharpness) * 0.25 +
		shard_noise(4.0 * uv, sharpness) * 0.5
	);
	// Radial mask so the puff has soft edges.
	vec2 centered = UV - vec2(0.5);
	float r = length(centered) * 2.0;
	float edge = 1.0 - smoothstep(1.0 - edge_fade, 1.0, r);
	float alpha = n * edge * life_alpha;
	// Respect the node's per-instance modulate (incoming COLOR) so callers can TINT
	// the smoke instead of every puff reading the flat default gray. Default white
	// modulate → identical to before (Roman worklist #44: "smoke sprites read gray,
	// not accepting color").
	COLOR = vec4(smoke_color.rgb * COLOR.rgb, alpha * smoke_color.a * COLOR.a);
}
