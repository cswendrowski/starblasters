shader_type canvas_item;
render_mode blend_mul; // Sets the hardware blend mode to multiply

void fragment() {
    // Sample the node's current texture
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Combine the texture alpha with the node's overall modulate alpha
    float effective_alpha = tex_color.a * COLOR.a;
    
    // Interpolate toward white based on alpha so fading out works correctly
    COLOR.rgb = mix(vec3(1.0), tex_color.rgb, effective_alpha);
    COLOR.a = effective_alpha;
}
