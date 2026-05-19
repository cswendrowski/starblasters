// Masked shadow shader. Casts a silhouette of TEXTURE darkened to a
// configurable color, multiplied per-pixel by a separate receiver mask
// texture. The shadow only renders where BOTH the caster's silhouette
// AND the receiver's mask have alpha — gives a sprite-shaped shadow
// clipped to the receiver's painted shape (Roman 2026-05-18).
//
// Caller responsibilities each frame:
//   * Set `mask_tex` to the current receiver's mask. If no receiver,
//     bind a transparent dummy or set `mask_active=false`.
//   * Set `shadow_world_origin` / `shadow_size_world` to the shadow
//     sprite's world-space top-left + size.
//   * Set `receiver_world_origin` / `receiver_size_world` to the
//     receiver's world-space top-left + size.
//
// The shader then computes each fragment's world position, converts to
// receiver-local UV, samples the mask, and multiplies.

shader_type canvas_item;
// Multiply blend so the shadow darkens whatever pixel is underneath it
// (Roman 2026-05-18 "40% opacity black, multiply").
render_mode blend_mul;

uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform bool mask_active = false;
// At max strength (caster.a × mask.a = 1) the output is mix(white, black, 0.4)
// = (0.6, 0.6, 0.6), which under blend_mul darkens the receiver to 60%.
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);

uniform vec2 shadow_world_origin = vec2(0.0, 0.0);
uniform vec2 shadow_size_world = vec2(48.0, 48.0);
uniform vec2 receiver_world_origin = vec2(0.0, 0.0);
uniform vec2 receiver_size_world = vec2(100.0, 100.0);

void fragment() {
	vec4 caster = texture(TEXTURE, UV);
	float strength = 0.0;
	if (caster.a > 0.01 && mask_active) {
		vec2 world_px = shadow_world_origin + UV * shadow_size_world;
		vec2 r_uv = (world_px - receiver_world_origin) / receiver_size_world;
		if (r_uv.x >= 0.0 && r_uv.x <= 1.0 && r_uv.y >= 0.0 && r_uv.y <= 1.0) {
			strength = texture(mask_tex, r_uv).a * caster.a * shadow_color.a;
		}
	}
	// blend_mul: COLOR.rgb is multiplied with the destination pixel. At
	// max strength we multiply by shadow_color.rgb (black) scaled by
	// (1 - strength); at zero strength we multiply by white = no-op.
	vec3 mul = mix(vec3(1.0), shadow_color.rgb, strength);
	COLOR = vec4(mul, 1.0);
}
