// Separable star glint — point core + thin cross diffraction rays, NO radial disc.
// Technique from "Starry Night" (godotshaders.com/shader/starry-night/, CC0): intensity is a
// SEPARABLE product of inverse axis distances — I = k / clamp(|dx|,0.5,half) / clamp(|dy|,0.5,half)
// in quad-local pixels — so the falloff is cross-shaped by construction. This is what makes the
// distant-star point read as a glint instead of the round blob every radial profile produces
// (Roman 2026-07-08, sparkle-tier round-core round 3).
shader_type canvas_item;
render_mode blend_add;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float quad_px = 48.0;        // this quad's size in px (spawner sets = rect size)
uniform float brightness = 2.0;      // k — core/ray energy (px² units; rays reach ~20×k px)
uniform float hdr_boost = 2.5;       // output multiplier so the core clears the 1.5 bloom threshold
uniform float ray_falloff = 1.0;     // >1 = shorter/tighter rays (power on the separable falloff)

void fragment() {
	vec2 d = abs(UV - 0.5) * quad_px;              // px from the quad center, per axis
	float half_px = quad_px * 0.5 - 1.0;
	float I = brightness / clamp(d.x, 0.5, half_px) / clamp(d.y, 0.5, half_px);
	I = pow(clamp(I, 0.0, 1.0), ray_falloff);
	// Window the quad edges so clipped rays fade instead of ending in a hard box edge.
	float w = 1.0 - smoothstep(0.36, 0.5, max(abs(UV.x - 0.5), abs(UV.y - 0.5)));
	I *= w;
	COLOR = vec4(color.rgb * I * hdr_boost, color.a * I);
}
