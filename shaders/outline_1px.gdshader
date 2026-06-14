shader_type canvas_item;

// Efficient 2D Pixel Outlines (Cody 2026-05-19) — branch-free neighbor
// sampling, configurable thickness + round/square corners.
//
// Defaults: black, 1-pixel round outline. Set `type = 2` for a square
// (8-neighbor) outline; thickness > 1 widens it. Texture filtering
// must be NEAREST (project default) so the alpha samples don't get
// interpolated edges. Sprite needs at least 1 transparent pixel of
// border or the outline has no transparent region to write into.
//
// Source: https://godotshaders.com/shader/efficient-2d-pixel-outlines/

uniform vec4 clr : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// type: 0 = disable, 1 = round (4-neighbor), 2 = square (8-neighbor).
uniform int type : hint_range(0, 2) = 1;
uniform float thickness = 1.0;

const vec2[8] DIRECTIONS = {
	vec2(1.0, 0.0),
	vec2(0.0, 1.0),
	vec2(-1.0, 0.0),
	vec2(0.0, -1.0),
	vec2(1.0, 1.0),
	vec2(-1.0, 1.0),
	vec2(-1.0, -1.0),
	vec2(1.0, -1.0)
};

float gtz(float input) { return max(0.0, sign(input)); }

// The neighbour alpha-sampling is INLINED in fragment() on purpose. `TEXTURE` is a
// fragment-stage built-in and is NOT a valid identifier inside a user function — referencing
// it in a helper makes forward_plus (and the headless dummy renderer) fail the WHOLE shader
// with "Unknown identifier 'TEXTURE'", which silently dropped every enemy/asteroid outline.
// Passing it as a `sampler2D` param instead trips the custom_samplers codegen check. Inlining
// is the only form that compiles under forward_plus. (Fix 2026-06-14; prior helper-fn broke it.)
void fragment() {
	float result = 0.0;
	for (int i = 0; i < 4 * type; i++) {
		result += texture(TEXTURE, UV + DIRECTIONS[i] * TEXTURE_PIXEL_SIZE * thickness).a;
	}
	COLOR = mix(COLOR, clr, gtz(result) * (1.0 - gtz(COLOR.a)));
}
