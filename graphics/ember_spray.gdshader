shader_type particles;

// Burning-debris ember spray (Roman 2026-06-10). A cone of stretched streaks
// whose colour over life is read from a TUNABLE gradient (`color_ramp`, a
// GradientTexture1D built by EmberFx / the Shader Lab): t=0 = hottest (birth),
// t=1 = charred (end of life). `invert` flips the read so the embers HEAT UP
// (char → white) instead of cooling. Driven by EmberFx on a one-shot
// GPUParticles2D whose texture is a 2×2 white pixel — all of the look is here.

uniform float direction_angle = -1.570796; // radians; -PI/2 = screen-up
uniform float spread_deg : hint_range(0.0, 180.0) = 35.0;
uniform float speed_min = 110.0;
uniform float speed_max = 320.0;
uniform float drag : hint_range(0.0, 10.0) = 2.6;
uniform float gravity_y = 30.0;
// Streak length in px = current speed × streak_sec, so streaks shorten as drag
// bleeds the velocity (rays collapse into dots near the end).
uniform float streak_sec : hint_range(0.0, 0.2) = 0.05;
uniform float thickness = 1.0; // streak thickness in px
// 0 = every ember cools on the same clock; 1 = fast embers cool much sooner.
uniform float cool_bias : hint_range(0.0, 1.0) = 0.55;
// Life fraction where the alpha fade-out begins.
uniform float fade_start : hint_range(0.0, 1.0) = 0.78;
// Per-ember lifetime jitter (fraction of LIFETIME shaved off the unlucky ones).
uniform float lifetime_rand : hint_range(0.0, 1.0) = 0.4;
// 0 = cool (gradient read t: white→char as the ember ages); 1 = heat up.
uniform float invert : hint_range(0.0, 1.0) = 0.0;
// Tunable colour ramp. t=0 = hottest, t=1 = charred. Set by EmberFx.
uniform sampler2D color_ramp : repeat_disable, filter_linear;

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
	float u = (invert > 0.5) ? (1.0 - t) : t;
	return texture(color_ramp, vec2(clamp(u, 0.0, 1.0), 0.5)).rgb;
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

	CUSTOM.x = r_spd;                                // speed norm → cooling rate
	CUSTOM.y = 0.0;                                  // age phase
	CUSTOM.z = 1.0 - lifetime_rand * (1.0 - r_life); // per-ember lifetime mult
	COLOR = vec4(ramp(0.0), 1.0);
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
	float t = clamp(life * cool_rate, 0.0, 1.0);
	float a = 1.0 - smoothstep(fade_start, 1.0, life);
	COLOR = vec4(ramp(t), a);

	// Stretch the quad along the velocity. The texture is 2 px across, so a
	// basis-column length of L renders 2·L px → halve the target sizes.
	float spd = length(VELOCITY.xy);
	vec2 dir = (spd > 0.5) ? VELOCITY.xy / spd : vec2(1.0, 0.0);
	float len_px = max(thickness, spd * streak_sec);
	TRANSFORM[0].xyz = vec3(dir * (len_px * 0.5), 0.0);
	TRANSFORM[1].xyz = vec3(vec2(-dir.y, dir.x) * (thickness * 0.5), 0.0);
}
