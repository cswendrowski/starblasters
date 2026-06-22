shader_type canvas_item;

uniform float sensitivity : hint_range(0.0, 1.0) = 0.0;
const float edge_width = .15;
uniform sampler2D noise_texture : repeat_enable;
uniform vec2 noise_config_size = vec2(64.0, 64.0);
uniform float noise_seed : hint_range(0.0, 999.0) = 0.0;

uniform vec4 replace_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.984, 0.949, 0.212, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 details_color : source_color = vec4(0.85, 0.45, 0.05, 1.0);
uniform float details_opacity : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D edge_distance_map : repeat_enable, filter_nearest;
uniform float edge_bias_strength : hint_range(0.0, 1.0) = 0.4;
uniform float edge_remap_min : hint_range(0.0, 1.0) = 0.0;
uniform float edge_remap_max : hint_range(0.0, 1.0) = 1.0;

// Overall strength of the damage tint (Roman 2026-06-08): cap so the sprite never
// fully blacks out — 0.6 keeps ~40% of the original showing through.
uniform float max_strength : hint_range(0.0, 1.0) = 0.6;
// White hit-flash, driven per-hit by enemy_base (so the flash lives ON the damage
// material instead of needing a second material slot the damage shader occupies).
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Final RGB scale (Roman 2026-06-21). Default 1.0 = no change (combat/enemies untouched);
// the outpost dock screen sets it < 1.0 to darken the parked ship to match the dim hangar.
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

const float epsilon = 0.01;

// Sprite-local vertex position, stable across animation frames.
// UV shifts when a sprite sheet frame changes; VERTEX does not.
varying vec2 v_local_pos;

bool compare_colors(vec4 c1, vec4 c2) {
    return abs(c1.r - c2.r) < epsilon && abs(c1.g - c2.g) < epsilon
        && abs(c1.b - c2.b) < epsilon && abs(c1.a - c2.a) < epsilon;
}

float seeded_noise(float seed) {
    return fract(sin(seed * 12.9898) * 43758.5453);
}

void vertex() {
    v_local_pos = VERTEX;
}

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    if (color.a < 0.01 || compare_colors(color, outline_color)) {
        // Transparent / outline pixels: skip the damage tint, but still flash white
        // (scaled by alpha so transparent pixels stay transparent).
        COLOR = vec4(mix(color.rgb, flash_color.rgb, flash_strength * color.a), color.a);
    } else {
        // Use sprite-local pixel coordinates for the noise lookup so the
        // pattern is stable regardless of which animation frame is active.
        // The old path used atlas UV (which shifts per frame on a sprite
        // sheet), causing the noise pattern to change with each frame.
        vec2 stable_px = floor(v_local_pos);
        vec2 base_noise_size = max(noise_config_size, vec2(1.0));
        vec2 random_offset = vec2(seeded_noise(noise_seed), seeded_noise(noise_seed + 1.0));
        vec2 noise_uv = stable_px / base_noise_size + random_offset;
        float noise_value = texture(noise_texture, noise_uv).r;
        float edge_distance = texture(edge_distance_map, UV).r;
        edge_distance = clamp((edge_distance - edge_remap_min) / (edge_remap_max - edge_remap_min), 0.0, 1.0);
        float edge_bias = (1.0 - edge_distance) * edge_bias_strength;
        float biased_sensitivity = clamp(sensitivity + edge_bias, 0.0, 1.0);
        float edge_lower = biased_sensitivity - edge_width;
        float edge_upper = biased_sensitivity + edge_width;
        float factor = smoothstep(edge_lower, edge_upper, noise_value);
        vec4 color1 = mix(replace_color, edge_color, factor);
        vec4 finalColor = mix(color1, color, factor);
        if (compare_colors(color, details_color)) {
            finalColor = mix(finalColor, details_color, details_opacity);
        }
        // Cap the damage tint at max_strength (never fully black out), then apply the
        // white hit-flash on top.
        vec3 damaged = mix(color.rgb, finalColor.rgb, max_strength);
        vec3 outc = mix(damaged, flash_color.rgb, flash_strength);
        COLOR = vec4(outc, color.a);
    }
    COLOR.rgb *= brightness;   // default 1.0 → no-op everywhere except the dimmed dock ship
}
