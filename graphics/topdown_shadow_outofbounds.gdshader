// Topdown shadow that can extend outside the sprite's own bounds.
//
// Source: https://godotshaders.com/shader/2d-topdown-shadow-that-goes-out-of-bounds/
// Author: Bettiold | License: CC0 (Public Domain)
// Stashed in reserve for later use (Roman, 2026-05-18).
//
// Uniforms:
//   r      — rotation of the shadow direction (radians)
//   offset — 0..1 shadow displacement away from the sprite
//
// Trick: the vertex shader scales the quad up 3× so the shadow can render
// outside the sprite's normal bounds. Fragment shader samples the texture
// at a rotated/offset UV for the shadow and at the un-offset UV for the
// real sprite, then composites.
//
// Per the page's own comments, initialising `shadow`/`real` to zero
// suppresses an artifact where uninitialised values leak through. Done
// below.

shader_type canvas_item;

uniform float r = 0.0;
uniform float offset : hint_range(0.0, 1.0) = 0.0;
// When true, output ONLY the displaced shadow — drops the real sprite
// pass. Useful when the shader is being used as a per-target shadow
// renderer (e.g. clipped under an asteroid to show a player shadow).
uniform bool shadow_only = false;

void vertex() {
	VERTEX.xy *= 3.0;
}

void fragment() {
	mat2 rotation_matrix = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r)));
	mat2 scale_matrix = mat2(vec2(1.0, 0.0), vec2(0.0, TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y));
	vec2 uv = (((UV * 2.0 - 1.0) * 3.0 + 1.0) / 2.0 - vec2(0.5)) * scale_matrix;
	vec2 uv_normal = uv * rotation_matrix * inverse(scale_matrix) + vec2(0.5);
	uv = (uv * rotation_matrix + vec2(0.25) * offset * rotation_matrix) * inverse(scale_matrix) + vec2(0.5);
	vec4 shadow = vec4(0.0, 0.0, 0.0, 0.0);
	vec4 real = vec4(0.0, 0.0, 0.0, 0.0);
	if (offset != 0.0 && uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec4 c = texture(TEXTURE, uv);
		shadow = vec4(0.0, 0.0, 0.0, c.a - 0.6);
	}
	if (uv_normal.x >= 0.0 && uv_normal.x <= 1.0 && uv_normal.y >= 0.0 && uv_normal.y <= 1.0) {
		real = texture(TEXTURE, uv_normal);
	}
	if (shadow_only) {
		// Cast straight down: the unshifted (real) sprite IS the shadow.
		COLOR = vec4(0.0, 0.0, 0.0, real.a * 0.55);
	} else {
		COLOR = mix(shadow, real, real.a);
	}
}
