// Hit-flash shader. Drives a sprite toward `flash_color` based on
// `flash_strength`. At 0.0 the sprite renders normally; at 1.0 the sprite is
// fully replaced by the flash color (alpha preserved). Used by hit_flash_fx
// to punch white on hull hits and shield-blue on shield hits.
shader_type canvas_item;

uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 mixed = mix(tex.rgb, flash_color.rgb, flash_strength);
	// Multiply by the built-in COLOR varying so the node's modulate (tint AND
	// alpha) is honored. Without this, a sprite that sets modulate.a (e.g. the
	// player ship going semi-transparent in focus mode) stays fully opaque once
	// this material is installed, since alpha would come only from the texture.
	// Identity for opaque-white modulate, so enemies/mines are unaffected.
	COLOR = vec4(mixed, tex.a) * COLOR;
}
