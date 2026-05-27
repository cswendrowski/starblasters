shader_type canvas_item;

uniform float sensitivity : hint_range(0.0, 1.0) = 0.0;
const float edge_width = .15;
uniform sampler2D noise_texture : repeat_enable;
uniform vec2 noise_config_size = vec2(64.0, 64.0);
uniform float noise_seed : hint_range(0.0, 999.0) = 0.0;

uniform vec4 replace_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.85, 0.45, 0.05, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 details_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float details_opacity : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D edge_distance_map : repeat_enable, filter_nearest;
uniform float edge_bias_strength : hint_range(0.0, 1.0) = 0.4;
uniform float edge_remap_min : hint_range(0.0, 1.0) = 0.0;
uniform float edge_remap_max : hint_range(0.0, 1.0) = 1.0;

const float epsilon = 0.01;

bool compare_colors(vec4 c1, vec4 c2) {
    return abs(c1.r - c2.r) < epsilon && abs(c1.g - c2.g) < epsilon
        && abs(c1.b - c2.b) < epsilon && abs(c1.a - c2.a) < epsilon;
}

float seeded_noise(float seed) {
    return fract(sin(seed * 12.9898) * 43758.5453);
}

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    if (color.a < 0.01 || compare_colors(color, outline_color)) {
        COLOR = color;
    } else {
        float size_x = float(textureSize(TEXTURE, 0).x);
        float size_y = float(textureSize(TEXTURE, 0).y);
        vec2 UVr = vec2(floor(UV.x * size_x) / size_x, floor(UV.y * size_y) / size_y);
        vec2 sprite_size = vec2(size_x, size_y);
        vec2 base_noise_size = max(noise_config_size, vec2(1.0));
        vec2 noise_scale = sprite_size / base_noise_size;
        vec2 random_offset = vec2(seeded_noise(noise_seed), seeded_noise(noise_seed + 1.0));
        vec2 noise_uv = vec2(UVr.x * noise_scale.x, UVr.y * noise_scale.y) + random_offset;
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
        COLOR = vec4(finalColor.rgb, color.a);
    }
}
