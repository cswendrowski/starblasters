shader_type particles;

// Ember spray — SMOKE-TAIL variant (Roman 2026-06-10). Same launch + cooling
// as ember_spray.gdshader, but instead of fading out shortly after charring,
// each ember drops to a dim smoke grey and LINGERS for most of its (longer)
// life, slowly fading — so the spray leaves a hanging tail of smoke after the
// fire dies. Drag bleeds the velocity so the late smoke reads as a drifting
// dot, not a streak.
//
// Two phases over life:
//   [0 .. cool_end]  burn  — white → yellow → orange → red → char, alpha ~1
//   [cool_end .. 1]  smoke — dim grey, alpha smoke_alpha fading slowly to 0

uniform float direction_angle = -1.570796; // radians; -PI/2 = screen-up
uniform float spread_deg : hint_range(0.0, 180.0) = 35.0;
uniform float speed_min = 110.0;
uniform float speed_max = 320.0;
uniform float drag : hint_range(0.0, 10.0) = 2.6;
uniform float gravity_y = 30.0;
uniform float streak_sec : hint_range(0.0, 0.2) = 0.05;
uniform float thickness = 1.0;
uniform float cool_bias : hint_range(0.0, 1.0) = 0.55;
uniform float lifetime_rand : hint_range(0.0, 1.0) = 0.4;
// Life fraction at which the ember has fully charred and the smoke phase begins.
// Small value = short flame, long smoke tail.
uniform float cool_end : hint_range(0.1, 0.9) = 0.34;
// Smoke colour + how opaque the lingering smoke starts (it fades to 0 by death).
uniform vec3 smoke_color : source_color = vec3(0.10, 0.095, 0.09);
uniform float smoke_alpha : hint_range(0.0, 1.0) = 0.42;

// fade_start kept for API parity with the other ember variants (unused detail
// here — the smoke phase owns the long fade).
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

	VELOCITY.xy *= max(0.0, 1.0 - drag * DELTA);
	VELOCITY.y += gravity_y * DELTA;

	float cool_rate = mix(1.0, mix(0.7, 1.6, CUSTOM.x), cool_bias);
	vec3 col;
	float a;
	if (life < cool_end) {
		// Burn: cool white → char over the short flame phase.
		float ct = clamp((life / max(cool_end, 0.001)) * cool_rate, 0.0, 1.0);
		col = ramp(ct);
		a = 1.0;
	} else {
		// Smoke: dim grey lingering, slow linear fade across the long tail.
		float st = (life - cool_end) / max(1.0 - cool_end, 0.001);
		col = smoke_color;
		a = smoke_alpha * (1.0 - st);
	}
	COLOR = vec4(col, a);

	float spd = length(VELOCITY.xy);
	vec2 dir = (spd > 0.5) ? VELOCITY.xy / spd : vec2(1.0, 0.0);
	float len_px = max(thickness, spd * streak_sec);
	TRANSFORM[0].xyz = vec3(dir * (len_px * 0.5), 0.0);
	TRANSFORM[1].xyz = vec3(vec2(-dir.y, dir.x) * (thickness * 0.5), 0.0);
}
