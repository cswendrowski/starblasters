// Black Hole — authored from scratch for this project.
//
// The reference "Black Hole Extended" from godotshaders.com is a `shader_type
// spatial` (3D) shader that ray-marches an accretion disk in view space; it
// cannot be dropped into a 2D `canvas_item` project. This shader keeps the
// same visual ingredients (dark event horizon, lensing warp of the background,
// bright accretion ring with hot/cool/edge bands, swirling turbulence) but
// implemented as a 2D radial fragment effect suitable for a ColorRect on a
// CanvasItem in Godot 4.3 `gl_compatibility`.
//
// Screen-texture sampling: `hint_screen_texture` is supported on the
// gl_compatibility renderer in Godot 4.3, but the back-buffer is not
// auto-populated for canvas items without a BackBufferCopy in the tree.
// The accompanying scene `scenes/hazards/black_hole.tscn` includes a
// BackBufferCopy with `copy_mode = COPY_MODE_VIEWPORT` to ensure SCREEN_TEXTURE
// has valid contents under both Forward+ and gl_compatibility.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Radii are expressed in UV units (0..1 across the quad). The quad is square
// and centered at (0.5, 0.5).
uniform float event_horizon : hint_range(0.0, 0.5) = 0.18;
uniform float photon_ring   : hint_range(0.0, 0.5) = 0.22;
uniform float disk_inner    : hint_range(0.0, 0.5) = 0.24;
uniform float disk_outer    : hint_range(0.0, 0.5) = 0.46;

// Lensing pulls neighbouring screen pixels toward the singularity within
// `lens_radius`. `lens_strength` scales the radial warp magnitude.
uniform float lens_radius   : hint_range(0.0, 0.6) = 0.48;
uniform float lens_strength : hint_range(0.0, 1.5) = 0.55;

// Accretion disk spin / turbulence / brightness controls.
uniform float spin_speed       : hint_range(-4.0, 4.0) = 1.4;
uniform float turbulence_scale : hint_range(0.5, 12.0) = 5.0;
uniform float ring_intensity   : hint_range(0.0, 6.0) = 2.4;
uniform float doppler_boost    : hint_range(0.0, 1.5) = 0.65;

uniform vec3 color_hot   : source_color = vec3(1.00, 0.95, 0.75);
uniform vec3 color_mid   : source_color = vec3(1.00, 0.55, 0.18);
uniform vec3 color_edge  : source_color = vec3(0.55, 0.10, 0.40);
uniform vec3 color_core  : source_color = vec3(0.00, 0.00, 0.00);

// Fade controls the overall opacity (used by the gd script during spawn / die).
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv - vec2(0.5);
	float r = length(p);
	float ang = atan(p.y, p.x);

	// --- Gravitational lensing of the background -----------------------------
	// Pull the sampled screen UV toward the centre. Falloff is 1/r^2-ish but
	// clamped near the horizon so the singularity doesn't explode into NaN.
	vec2 dir_to_center = -p / max(r, 1e-4);
	float lens_t = 1.0 - smoothstep(event_horizon, lens_radius, r);
	float warp = lens_strength * lens_t * lens_t / (r * 8.0 + 0.25);
	vec2 screen_uv = SCREEN_UV + dir_to_center * warp * 0.08;
	screen_uv = clamp(screen_uv, vec2(0.001), vec2(0.999));
	vec3 bg = texture(SCREEN_TEXTURE, screen_uv).rgb;

	// --- Accretion disk ------------------------------------------------------
	// Treat the disk as a flat annular ring around the centre. Coordinates
	// rotate over time; turbulence is fbm in polar space.
	float t = TIME;
	vec2 polar = vec2(ang / 6.2831853 + t * spin_speed * 0.02, log(max(r, 0.001)) * turbulence_scale);
	float turb = fbm(polar * vec2(3.0, 1.0) + vec2(t * 0.15, 0.0));

	float disk_mask = smoothstep(disk_inner - 0.01, disk_inner + 0.02, r)
	                * (1.0 - smoothstep(disk_outer - 0.05, disk_outer, r));
	// Banded brightness across the disk: hottest at the inner edge.
	float band = 1.0 - clamp((r - disk_inner) / max(disk_outer - disk_inner, 0.001), 0.0, 1.0);
	float intensity = disk_mask * (0.45 + 0.9 * turb) * pow(band, 1.6) * ring_intensity;

	// Doppler / relativistic beaming: one side of the disk is brighter as it
	// rotates toward the camera. Sin(ang) gives the asymmetry, sign tied to
	// spin_speed so reversing spin flips the bright lobe.
	float beam = 1.0 + doppler_boost * sin(ang) * sign(spin_speed);
	intensity *= max(beam, 0.0);

	vec3 disk_color = mix(color_edge, color_mid, smoothstep(0.0, 0.5, band));
	disk_color = mix(disk_color, color_hot, smoothstep(0.5, 1.0, band));

	// Photon ring: a thin bright halo just outside the horizon.
	float ring = exp(-pow((r - photon_ring) * 80.0, 2.0));
	vec3 ring_col = color_hot * ring * 1.8;

	// --- Event horizon -------------------------------------------------------
	// Hard black core; smoothly blends into the lensed background.
	float horizon = 1.0 - smoothstep(event_horizon - 0.02, event_horizon + 0.005, r);
	vec3 col = bg;
	col += disk_color * intensity;
	col += ring_col;
	col = mix(col, color_core, horizon);

	// Outer alpha: the quad is bigger than the effect, so feather to 0
	// past the lens radius so it composites cleanly over the scene.
	float outer_alpha = 1.0 - smoothstep(lens_radius, lens_radius + 0.04, r);
	// Inside the lens radius we always want to draw (we need the lensed bg).
	float alpha = max(outer_alpha, horizon + clamp(intensity, 0.0, 1.0) + ring);
	alpha = clamp(alpha, 0.0, 1.0) * fade;

	COLOR = vec4(col, alpha);
}
