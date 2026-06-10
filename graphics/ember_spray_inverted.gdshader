shader_type particles;

// Ember spray — INVERTED ramp variant (Roman 2026-06-10). Identical mechanics
// to ember_spray.gdshader (cone of velocity-stretched streaks driven by
// EmberFx), but the color progression runs the OTHER way: each ember starts
// charred-dark and HEATS UP toward white-hot as it ages, instead of cooling
// from white to char. Reads as sparks igniting / re-kindling debris rather
// than spent embers dying out.
//
// Ramp (reverse of the original): 100605 → 8a1000 → ff4b00 → fbd12f → ffffff.
// `cool_bias` here biases by speed too, so FAST embers reach white-hot sooner
// (bright leading tips, dark slow tail near the origin).

uniform float direction_angle = -1.570796; // radians; -PI/2 = screen-up
uniform float spread_deg : hint_range(0.0, 180.0) = 35.0;
uniform float speed_min = 110.0;
uniform float speed_max = 320.0;
uniform float drag : hint_range(0.0, 10.0) = 2.6;
uniform float gravity_y = 30.0;
uniform float streak_sec : hint_range(0.0, 0.2) = 0.05;
uniform float thickness = 1.0; // streak thickness in px
uniform float cool_bias : hint_range(0.0, 1.0) = 0.55;
uniform float fade_start : hint_range(0.0, 1.0) = 0.78;
uniform float lifetime_rand : hint_range(0.0, 1.0) = 0.4;

// Color-ramp stops: the heating fraction where each color is fully reached.
uniform float stop_yellow = 0.16;
uniform float stop_orange = 0.38;
uniform float stop_red = 0.62;
uniform float stop_black = 0.85;

const vec3 C_WHITE = vec3(1.0, 1.0, 1.0);        // ffffff
const vec3 C_YELLOW = vec3(0.984, 0.820, 0.184); // fbd12f
const vec3 C_ORANGE = vec3(1.0, 0.294, 0.0);     // ff4b00
const vec3 C_RED = vec3(0.541, 0.063, 0.0);      // 8a1000
const vec3 C_BLACK = vec3(0.063, 0.024, 0.020);  // 100605

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

// INVERTED order: dark char heats up to white-hot.
vec3 ramp(float t) {
	if (t < stop_yellow) {
		return mix(C_BLACK, C_RED, t / max(stop_yellow, 0.001));
	} else if (t < stop_orange) {
		return mix(C_RED, C_ORANGE, (t - stop_yellow) / max(stop_orange - stop_yellow, 0.001));
	} else if (t < stop_red) {
		return mix(C_ORANGE, C_YELLOW, (t - stop_orange) / max(stop_red - stop_orange, 0.001));
	} else if (t < stop_black) {
		return mix(C_YELLOW, C_WHITE, (t - stop_red) / max(stop_black - stop_red, 0.001));
	}
	return C_WHITE;
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

	CUSTOM.x = r_spd;                                // speed norm → heating rate
	CUSTOM.y = 0.0;                                  // age phase
	CUSTOM.z = 1.0 - lifetime_rand * (1.0 - r_life); // per-ember lifetime mult
	COLOR = vec4(C_BLACK, 1.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float life = CUSTOM.y / max(CUSTOM.z, 0.05);
	if (life >= 1.0) {
		ACTIVE = false;
	}

	VELOCITY.xy *= max(0.0, 1.0 - drag * DELTA);
	VELOCITY.y += gravity_y * DELTA;

	float heat_rate = mix(1.0, mix(0.7, 1.6, CUSTOM.x), cool_bias);
	float t = clamp(life * heat_rate, 0.0, 1.0);
	float a = 1.0 - smoothstep(fade_start, 1.0, life);
	COLOR = vec4(ramp(t), a);

	float spd = length(VELOCITY.xy);
	vec2 dir = (spd > 0.5) ? VELOCITY.xy / spd : vec2(1.0, 0.0);
	float len_px = max(thickness, spd * streak_sec);
	TRANSFORM[0].xyz = vec3(dir * (len_px * 0.5), 0.0);
	TRANSFORM[1].xyz = vec3(vec2(-dir.y, dir.x) * (thickness * 0.5), 0.0);
}
