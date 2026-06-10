shader_type particles;

// Ember spray — SMOKE-TAIL variant (Roman 2026-06-10, reworked).
// Each ember is a streak that behaves in two phases over its life:
//
//   TRAVEL  (life < travel_frac): the leading tip flies outward, WHITE-HOT the
//           whole way, full alpha. The stretched streak is the trail and it
//           persists (doesn't fade) for the entire travel.
//   SETTLE  (life >= travel_frac): the tip has reached its endpoint — velocity
//           is zeroed and the streak FREEZES in place (its basis is simply left
//           untouched). Only NOW does the colour fade off white through
//           yellow → orange → red → char → smoke, and the whole frozen trail
//           fades out together.
//
// So: white tip for all of travel, colours only after the endpoint, and the
// trail lasts until the tip lands and then fades as one.

uniform float direction_angle = -1.570796; // radians; -PI/2 = screen-up
uniform float spread_deg : hint_range(0.0, 180.0) = 35.0;
uniform float speed_min = 110.0;
uniform float speed_max = 320.0;
uniform float drag : hint_range(0.0, 10.0) = 2.6;
uniform float gravity_y = 30.0;
uniform float streak_sec : hint_range(0.0, 0.2) = 0.05;
uniform float thickness = 1.0;
uniform float lifetime_rand : hint_range(0.0, 1.0) = 0.4;
// Fraction of life spent travelling (white) before the tip lands and settles.
uniform float travel_frac : hint_range(0.1, 0.95) = 0.5;
// Where in the settle phase the trail starts fading (0 = fade immediately).
uniform float fade_hold : hint_range(0.0, 0.9) = 0.15;
// Smoke grey the char drifts toward at the very end.
uniform vec3 smoke_color : source_color = vec3(0.10, 0.095, 0.09);

// kept for API parity with the other variants (unused here)
uniform float cool_bias : hint_range(0.0, 1.0) = 0.55;
uniform float fade_start : hint_range(0.0, 1.0) = 0.78;

uniform float stop_yellow = 0.16;
uniform float stop_orange = 0.38;
uniform float stop_red = 0.62;
uniform float stop_black = 0.85;

const vec3 C_WHITE = vec3(1.0, 1.0, 1.0);
const vec3 C_YELLOW = vec3(0.984, 0.820, 0.184);
const vec3 C_ORANGE = vec3(1.0, 0.294, 0.0);
const vec3 C_RED = vec3(0.541, 0.063, 0.0);
const vec3 C_BLACK = vec3(0.063, 0.024, 0.020);

uint hash_u(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float rand01(inout uint seed) {
	seed = hash_u(seed);
	return float(seed % uint(65536)) / 65535.0;
}

// White → yellow → orange → red → char.
vec3 ramp(float t) {
	if (t < stop_yellow) {
		return mix(C_WHITE, C_YELLOW, t / max(stop_yellow, 0.001));
	} else if (t < stop_orange) {
		return mix(C_YELLOW, C_ORANGE, (t - stop_yellow) / max(stop_orange - stop_yellow, 0.001));
	} else if (t < stop_red) {
		return mix(C_ORANGE, C_RED, (t - stop_orange) / max(stop_red - stop_orange, 0.001));
	} else if (t < stop_black) {
		return mix(C_RED, C_BLACK, (t - stop_red) / max(stop_black - stop_red, 0.001));
	}
	return C_BLACK;
}

void start() {
	uint seed = hash_u(NUMBER * uint(2654435769) + RANDOM_SEED);
	float r_ang = rand01(seed);
	float r_spd = rand01(seed);
	float r_life = rand01(seed);

	float ang = direction_angle + radians(spread_deg) * (r_ang * 2.0 - 1.0);
	float spd = mix(speed_min, speed_max, r_spd);
	VELOCITY = vec3(cos(ang), sin(ang), 0.0) * spd;

	TRANSFORM[0] = vec4(1.0, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, 1.0, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, 1.0, 0.0);
	TRANSFORM[3] = EMISSION_TRANSFORM[3];

	CUSTOM.x = r_spd;
	CUSTOM.y = 0.0;
	CUSTOM.z = 1.0 - lifetime_rand * (1.0 - r_life);
	COLOR = vec4(C_WHITE, 1.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float life = CUSTOM.y / max(CUSTOM.z, 0.05);
	if (life >= 1.0) {
		ACTIVE = false;
	}

	if (life < travel_frac) {
		// TRAVEL: keep flying, white-hot, opaque. Streak stretched by velocity.
		VELOCITY.xy *= max(0.0, 1.0 - drag * DELTA);
		VELOCITY.y += gravity_y * DELTA;
		float spd = length(VELOCITY.xy);
		vec2 dir = (spd > 0.5) ? VELOCITY.xy / spd : vec2(1.0, 0.0);
		float len_px = max(thickness, spd * streak_sec);
		TRANSFORM[0].xyz = vec3(dir * (len_px * 0.5), 0.0);
		TRANSFORM[1].xyz = vec3(vec2(-dir.y, dir.x) * (thickness * 0.5), 0.0);
		COLOR = vec4(C_WHITE, 1.0);
	} else {
		// SETTLE: the tip has reached its endpoint. Stop dead and leave the
		// streak basis (TRANSFORM[0]/[1]) frozen — the trail holds its shape.
		// Now run the colour ramp off white and fade the whole trail out.
		VELOCITY = vec3(0.0);
		float sp = clamp((life - travel_frac) / max(1.0 - travel_frac, 0.001), 0.0, 1.0);
		vec3 col = ramp(sp);
		col = mix(col, smoke_color, smoothstep(0.7, 1.0, sp));
		float a = 1.0 - smoothstep(fade_hold, 1.0, sp);
		COLOR = vec4(col, a);
	}
}
