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

// Sample TEXTURE directly here rather than receiving it as a parameter. Passing the built-in
// sampler `TEXTURE` into a user function trips Godot's custom_samplers codegen check
// ("!custom_samplers.has(function->arguments[j].tex_builtin)"). gl_compatibility tolerated it;
// forward_plus (the 2026-06-10 pivot) hard-faults the combat pipeline on it. (Roman 2026-06-12)
float check(vec2 from, vec2 size) {
	float result = 0.0;
	for (int i = 0; i < 4 * type; i++) {
		result += texture(TEXTURE, from + DIRECTIONS[i] * size * thickness).a;
	}
	return gtz(result);
}

void fragment() {
	COLOR = mix(COLOR, clr, check(UV, TEXTURE_PIXEL_SIZE) * (1.0 - gtz(COLOR.a)));
}
