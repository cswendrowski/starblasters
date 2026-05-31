// Mid-depth tint for the MISSILE CRUISER body sprite. Unlike modulate /
// parallax_tint (both MULTIPLICATIVE — they can only dim/cool a color, never
// push a saturated red toward grey-blue), this LERPS the texture RGB toward a
// flat background color by `amount`, so the ship genuinely desaturates toward
// the backdrop and reads as living in the mid parallax layer.
//
//   amount 0.0 = untouched art; amount 1.0 = fully the tint color.
//
// Alpha is preserved so the silhouette stays intact for pixel art.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 bg_tint : source_color = vec4(0.42, 0.50, 0.62, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec3 mixed = mix(tex_color.rgb, bg_tint.rgb, amount);
	COLOR = vec4(mixed, tex_color.a);
}
