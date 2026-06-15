// Soft noise puff — a GPUParticles2D *CanvasItem* material that carves a tiled
// NoiseTexture2D into the particle's radial gradient, giving billowy, soft-edged,
// semi-transparent puffs. Cheaper than billow_smoke's procedural shard noise
// (one texture fetch vs a 27-tap loop) — use when you already have a noise .tres.
//
// All lifetime colour + alpha still comes from the ParticleProcessMaterial's
// color_ramp (the incoming COLOR), so the emitter's fade-out is preserved.
//
// Setup: assign as the GPUParticles2D *Material* (CanvasItem), NOT the Process
// Material. Keep the node's `texture` a radial GradientTexture2D — it both sizes
// the particle quad and supplies the soft round shape sampled below as TEXTURE.

shader_type canvas_item;

// Tiled grayscale noise, e.g. res://resources/noise_damage.tres. repeat_enable
// so noise_scale > 1 wraps cleanly (the .tres has seamless = true). Nearest to
// stay on-brand with the game's pixel-art filtering; swap to filter_linear for
// smoother, smokier billows.
uniform sampler2D noise_tex : repeat_enable, filter_nearest;
// Noise tiles across one particle quad. >1 = finer texture detail.
uniform float noise_scale : hint_range(0.25, 8.0) = 2.0;
// Push noise toward 0/1 so it reads as distinct billows, not flat gray.
uniform float noise_contrast : hint_range(0.0, 4.0) = 1.6;
// Scroll the noise field over time for living, churning puffs. 0 = static.
uniform vec2 noise_scroll = vec2(0.0, -0.15);

void fragment() {
	// Radial gradient from the node texture: soft round shape + alpha falloff.
	vec4 base = texture(TEXTURE, UV);

	// Tiled noise, scrolled and contrast-shaped.
	vec2 nuv = UV * noise_scale + TIME * noise_scroll;
	float n = texture(noise_tex, nuv).r;
	n = clamp((n - 0.5) * noise_contrast + 0.5, 0.0, 1.0);

	// COLOR carries the process material's color_ramp / over-life alpha.
	// Multiply gradient + noise into it: lifetime fade is preserved and noise
	// only ever *removes* opacity (never adds a hard edge).
	COLOR *= base;
	COLOR.a *= n;
}
