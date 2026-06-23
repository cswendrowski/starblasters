shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform float thickness : hint_range(0.0, 10.0) = 2.0;
uniform float glow_power : hint_range(0.0, 5.0) = 1.5;

void fragment() {
    // Calculate pixel size relative to texture
    vec2 size = TEXTURE_PIXEL_SIZE * thickness;
    
    // Sample the center pixel alpha
    float current_alpha = texture(TEXTURE, UV).a;
    
    // Sample 4 corners to detect the outer edge space
    float a = current_alpha;
    a = max(a, texture(TEXTURE, UV + vec2(size.x, 0.0)).a);
    a = max(a, texture(TEXTURE, UV + vec2(-size.x, 0.0)).a);
    a = max(a, texture(TEXTURE, UV + vec2(0.0, size.y)).a);
    a = max(a, texture(TEXTURE, UV + vec2(0.0, -size.y)).a);
    
    // Calculate where the outside border lives
    float outer_border = a - current_alpha;
    
    // Get original sprite texture color
    vec4 sprite_color = texture(TEXTURE, UV);
    
    // Mix the original sprite on top, and the outer glow strictly outside
    vec4 final_glow = outline_color * outer_border * glow_power;
    
    // Combine them without modifying original sprite colors
    COLOR = mix(final_glow, sprite_color, current_alpha);
}
