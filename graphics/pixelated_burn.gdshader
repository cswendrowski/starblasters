// Pixelated Burn shader — godotshaders.com/shader/pixelated-burn/
// Applied to a Sprite2D's material to "burn away" the sprite from a
// `position` outward as `radius` grows.
shader_type canvas_item;

uniform vec2 position = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float borderWidth = 0.18;
uniform float burnMult = 0.34;
uniform sampler2D noiseTexture;
uniform vec4 burnColor : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float pixel_size = 0.04;
uniform float blend_steps = 6.0;
uniform sampler2D colorCurve;

void fragment() {
	vec2 snapped_uv = floor(UV / pixel_size) * pixel_size;
	float dist = length(position - snapped_uv) + (texture(noiseTexture, snapped_uv).b) * burnMult;
	float mask = clamp((dist - (radius - borderWidth)) / (2.0 * borderWidth), 0.0, 1.0);
	mask = 1.0 - mask;
	mask = floor(mask * blend_steps) / blend_steps;
	vec4 curve_value = texture(colorCurve, vec2(mask, 0.0));
	float blendMask = pow(mask, 0.1);
	COLOR.rgb = mix(COLOR.rgb, curve_value.rgb, blendMask);
	COLOR.a *= min(COLOR.a, 1.0 - float(dist < radius));
}
