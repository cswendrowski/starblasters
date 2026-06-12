// Glow Effect 2D — color-keyed in-sprite emission (godotshaders.com/shader/glow-effect-2d/,
// "evaluate next to our current glow", Roman 2026-06-11). Unlike glow_halo.gdshader (a soft
// halo drawn BEHIND the sprite), this one boosts pixels of the sprite that MATCH color1/color2
// up to glow_color × intensity, so the WorldEnvironment bloom lights just those pixels. Pair
// with an env that has glow enabled.
shader_type canvas_item;

uniform vec4 color1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform float threshold : hint_range(0.0, 2.0) = 0.35;
uniform float intensity : hint_range(0.0, 4.0) = 1.6;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 glow_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);

void fragment() {
	vec4 pixel_color = texture(TEXTURE, UV);
	float distance = length(pixel_color - color1);
	float distance_second = length(pixel_color - color2);
	vec4 modified_glow_color = glow_color;
	modified_glow_color.a = opacity;
	if (distance < threshold || distance_second < threshold) {
		COLOR = mix(pixel_color, modified_glow_color * intensity, modified_glow_color.a);
		COLOR.a = pixel_color.a;   // keep the sprite's own alpha (don't bloom transparent pixels)
	} else {
		COLOR = pixel_color;
	}
}
