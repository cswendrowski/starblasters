shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D atlas : hint_default_white;
uniform int variant_count : hint_range(1, 32) = 10;
uniform int frame_count : hint_range(1, 32) = 13;
uniform float scroll_rot_speed : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	// Read INSTANCE_CUSTOM packed data (Color: x, y, z, w):
	// x = variant index (0..variant_count-1, as float)
	// y = phase (0..1, animation offset)
	// z, w = unused
	int variant_idx = int(INSTANCE_CUSTOM.x);
	float phase = INSTANCE_CUSTOM.y;

	// Clamp variant index to valid range
	variant_idx = clamp(variant_idx, 0, variant_count - 1);

	// Compute current frame from TIME + phase
	// Each frame rotates the asteroid 0..2*pi over frame_count frames
	float anim_t = fract(TIME * scroll_rot_speed + phase);
	int frame_idx = int(anim_t * float(frame_count)) % frame_count;

	// Map UV to atlas cell:
	// Atlas is laid out as: rows = variants, columns = frames
	// Each cell is (1/frame_count) wide × (1/variant_count) tall
	// UV.xy is local to the quad (0..1), map it into the cell

	float cell_width = 1.0 / float(frame_count);
	float cell_height = 1.0 / float(variant_count);

	// Base offset for this cell in the atlas
	float frame_u_offset = float(frame_idx) * cell_width;
	float variant_v_offset = float(variant_idx) * cell_height;

	// Sample UV within the cell
	vec2 atlas_uv = vec2(
		frame_u_offset + UV.x * cell_width,
		variant_v_offset + UV.y * cell_height
	);

	vec4 sampled = texture(atlas, atlas_uv);
	COLOR = sampled;
}
