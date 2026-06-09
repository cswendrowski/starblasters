shader_type canvas_item;

// 1. Color picker for the darkening tint
uniform vec4 tint_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);

// 2. Opacity slider from 0.0 (no effect) to 1.0 (full multiply)
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // Sample the sprite's texture to get the transparent shape mask
    vec4 sprite_tex = texture(TEXTURE, UV);
    
    // Sample the background behind the sprite
    vec4 screen_tex = texture(screen_texture, SCREEN_UV);
    
    // Calculate the full multiply effect
    vec3 dark_effect = screen_tex.rgb * tint_color.rgb;
    
    // Smoothly blend from the normal background to the darkened background using opacity
    vec3 final_rgb = mix(screen_tex.rgb, dark_effect, opacity);
    
    // Output the final blend, strictly confined to the sprite's alpha shape
    COLOR = vec4(final_rgb, sprite_tex.a);
}
