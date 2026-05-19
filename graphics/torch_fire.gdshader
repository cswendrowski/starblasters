//  Procedural Torch & Candle Shader (Fire + Smoke + Sparks)
//  Author: CaptainLaptop
//  Source: https://godotshaders.com/shader/procedural-torch-candle-shader-fire-smoke-sparks/
//  License: CC0 / MIT
//  Engine: Godot 4.x
//
//  Stashed and applied to the player engine plume (Roman 2026-05-18).
//
//  Description:
//  A fully procedural, particle-free fire simulation that
//  generates animated flames, sparks, and smoke using only math.
//
//  Ideal for candles, torches, and other small light sources.
//  Avoid large full-screen use as it can be fillrate-heavy.

shader_type canvas_item;


// =============================================================================
// GLOBAL CONTROL UNIFORMS
// =============================================================================

uniform float speed : hint_range(0.1, 5.0) = 1.0;
uniform float pixelSize : hint_range(0.001, 0.1) = 0.015;
uniform float alpha : hint_range(0.0, 1.0) = 0.95;
uniform float flickerStrength : hint_range(0.0, 0.5) = 0.15;

// =============================================================================
// COLOR & HUE UNIFORMS
// =============================================================================

uniform vec3 toColor : source_color = vec3(0.4, 0.35, 0.2);
uniform vec3 fromColor : source_color = vec3(0.9, 0.2, 0.1);

uniform float hueShift : hint_range(-1.0, 1.0) = 0.0;
uniform float saturationFactor : hint_range(0.0, 2.0) = 1.0;

// =============================================================================
// FIRE SIMULATION UNIFORMS
// =============================================================================

uniform float particleCount : hint_range(16.0, 512.0) = 128.0;
uniform float brightness : hint_range(0.0001, 0.01) = 0.001;

uniform float fireShift : hint_range(0.0, 0.5) = 0.15;
uniform float fireShiftFrequency : hint_range(1.0, 10.0) = 5.0;

uniform vec2 size = vec2(0.05, 0.75);
uniform vec2 glow = vec2(0.001, 0.04);

// =============================================================================
// SPARKS UNIFORMS
// =============================================================================

uniform float sparkCount : hint_range(1.0, 50.0) = 18.0;
uniform float sparkSize : hint_range(0.0005, 0.005) = 0.004;
uniform float sparkSpeed : hint_range(0.1, 3.0) = 0.15;
uniform vec3 sparkColor : source_color = vec3(1.0, 0.7, 0.0);

// =============================================================================
// SMOKE UNIFORMS
// =============================================================================

uniform float smokeCount : hint_range(5.0, 50.0) = 20.0;
uniform float smokeSize : hint_range(0.001, 0.05) = 0.015;
uniform float smokeDrift : hint_range(0.0, 0.5) = 0.2;
uniform vec3 smokeColor : source_color = vec3(0.05, 0.05, 0.05);

// =============================================================================
// ENVIRONMENT UNIFORMS
// =============================================================================

uniform float windForce : hint_range(-0.5, 0.5) = 0.0;
uniform float aspectRatio : hint_range(0.01, 5.0) = 1.0;
uniform vec2 posOffset = vec2(0.0, -0.5);


// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

float Hash1(float t) {
	return fract(cos(t * 124.97) * 248.842) - 0.5;
}

float saturate(float x) {
	return clamp(x, 0.0, 1.0);
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.w - q.y) / (6.0 * d + e) + q.z, d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.w);
	return c.z * mix(K.xxx, clamp(p - K.x, 0.0, 1.0), c.y);
}


// =============================================================================
// PARTICLE SIMULATION FUNCTIONS
// =============================================================================

vec3 Simulate(vec2 uv, float t) {
	vec3 res = vec3(0.0);
	for (float i = 0.0; i < particleCount; i++) {
		float ct = fract(t + (i + 1.0) / particleCount);
		float seed = Hash1((i + 1.0) * (t - ct));
		vec2 dir = vec2(0.0, size.y);
		dir.x += windForce;
		dir.x += (cos(t * seed) * sin(ct * fireShiftFrequency)) * mix(0.0, fireShift, log(ct));
		float cb = saturate(mix(brightness, 0.0, ct));
		vec2 off = vec2(seed * size.x, 0.0);
		res += mix(fromColor * abs(seed), toColor, ct)
			* smoothstep(glow.x, glow.y, cb / length((uv - off - (dir * ct))));
	}
	return res;
}

vec3 SimulateSparks(vec2 uv, float t) {
	vec3 sparkRes = vec3(0.0);
	t *= sparkSpeed;
	for (float i = 0.0; i < sparkCount; i++) {
		float particleId = (i + 1.0) * 133.0;
		float ct = fract(t + particleId / 100.0);
		float seed = Hash1(particleId);
		vec2 dir = vec2(seed * 0.4, size.y * 2.5);
		dir.x += windForce * 2.0;
		vec2 particle_center = vec2(seed * size.x * 0.3, 0.0) + (dir * ct);
		float dist = length(uv - particle_center);
		float particle_influence = saturate(1.0 - dist / (sparkSize * 5.0));
		float glow_falloff = pow(particle_influence, 15.0);
		float lifespan_fade = saturate(1.0 - ct * 2.0);
		sparkRes += sparkColor * glow_falloff * lifespan_fade * 100.0;
	}
	return sparkRes;
}

vec3 SimulateSmoke(vec2 uv, float t) {
	vec3 smokeRes = vec3(0.0);
	for (float i = 0.0; i < smokeCount; i++) {
		float particleId = (i + 1.0) * 111.0;
		float ct = fract(t * 0.5 + particleId / 100.0);
		float seed = Hash1(particleId);
		vec2 dir = vec2(seed * smokeDrift, size.y * 1.5);
		dir.x += windForce * 0.8;
		float cb = saturate(mix(brightness * 10.0, 0.0, ct * 1.5));
		vec2 off = vec2(seed * size.x * 0.5, size.y * 0.6);
		smokeRes += smokeColor * smoothstep(smokeSize, smokeSize * 2.0,
			cb / length((uv - off - (dir * ct))));
	}
	return smokeRes;
}


// =============================================================================
// FRAGMENT MAIN
// =============================================================================

void fragment() {
	vec2 frag_coords = UV * 2.0 - 1.0;
	frag_coords.x *= aspectRatio;
	frag_coords.y *= -1.0;
	frag_coords -= posOffset;

	vec2 pixelated_frag = floor(frag_coords / pixelSize) * pixelSize;

	float base_time = TIME + 100.0;

	vec3 fire_color = Simulate(pixelated_frag, base_time * speed);
	vec3 spark_color = SimulateSparks(pixelated_frag, base_time);
	vec3 smoke_color = SimulateSmoke(pixelated_frag, base_time);

	vec3 result_color = fire_color + spark_color + smoke_color;

	vec3 hsv = rgb_to_hsv(result_color);
	hsv.x = fract(hsv.x + hueShift);
	hsv.y *= saturationFactor;
	result_color = hsv_to_rgb(hsv);

	float flicker = (Hash1(base_time * 5.0) + 0.5) * flickerStrength;
	float intensity_mod = 1.0 + flicker;
	vec3 final_color = result_color * intensity_mod;

	float intensity = max(max(result_color.r, result_color.g), result_color.b);
	float final_alpha = smoothstep(0.01, 0.5, intensity) * alpha;

	COLOR = vec4(final_color * alpha, final_alpha);
}
