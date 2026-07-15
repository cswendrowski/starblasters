shader_type canvas_item;
render_mode blend_mix;

// --- Adapted from "2D Top-Down Oblique Shadow" (shadecore_dev, godotshaders.com, CC0) ---
// Roman 2026-07-13: reworked to cast a FLAT-silhouette oblique shadow for top-down building sprites that
// have NO heightmap. The occluder "height" is the sprite's own ALPHA (its silhouette), sampled from the
// `src_tex` uniform (the building layer's sheet) via an explicit `frame_region` — so it works on an hframe
// atlas AND can project the shadow onto a CARRIER surface (a ColorRect) larger than the sprite. Shadow-only
// by default (draw_albedo off): the real building layer draws separately ON TOP; this sits BEHIND on the
// ground. Tuned in the Shader Lab "Building Shadow" mode (per building, per layer) → Copy → baked.
//
// The occluder is flat (all silhouette pixels = height_scale), so the ray-march reads as an oblique DROP
// shadow whose LENGTH is set by height_scale (taller ⇒ longer) and sun_elevation (higher ⇒ shorter), capped
// by steps × step_px. sun_dir.xy is the light direction (shadow falls opposite).

// --- Carrier: this material lives on a ColorRect sized carrier_scale× the sprite frame, centred on it.
// to_local() maps the carrier's UV → frame-local [0,1]; outside the frame there is no occluder.
uniform float carrier_scale = 2.5;       // ColorRect size ÷ sprite-frame size (room for the projected shadow)
uniform float carrier_size_px = 40.0;    // the ColorRect's square size in px (drives px→uv step conversion)

// --- Occluder source: the building LAYER's full texture (sheet) + the drawn frame's UV sub-rect.
uniform sampler2D src_tex : filter_nearest, repeat_disable;
uniform vec4 frame_region = vec4(0.0, 0.0, 1.0, 1.0);   // (u0, v0, uw, vh) of the frame within src_tex
uniform float alpha_cutoff = 0.05;
uniform float height_scale = 1.0;        // silhouette "height" — taller ⇒ LONGER shadow

// --- Light / projection.
uniform vec2 sun_dir = vec2(0.45, 0.85); // xy direction of the light in UV space (shadow falls opposite)
uniform float sun_elevation = 0.45;      // higher ⇒ ray rises faster ⇒ SHORTER shadow
uniform float step_px = 1.0;             // ray-march step in px (bigger = faster, coarser)
uniform int steps = 40;                  // max march iterations (× step_px = max reach)
uniform float shadow_ray_offset_px = 0.0;// push the ray origin off the silhouette edge (kills inner artifacts)
uniform float shadow_softness = 0.08;    // edge feather
uniform bool shadow_aa_enabled = true;
uniform float shadow_aa_radius_px = 0.75;

// --- Look.
uniform float shadow_strength = 0.6;     // 0..1 darkness
uniform vec4 shadow_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool draw_albedo = false;        // false = shadow-only node (default); true = self-contained sprite+shadow
uniform bool shadow_on_footprint = false;// false = keep the cast shadow OFF the silhouette footprint (building draws there)

const int MAX_STEPS = 96;


// carrier-UV → frame-local [0,1]. Content is centred, occupying 1/carrier_scale of the carrier.
vec2 to_local(vec2 uv) {
	float cs = max(carrier_scale, 1e-4);
	float o = 0.5 - 0.5 / cs;
	return (uv - vec2(o)) * cs;
}


// Flat silhouette height at a carrier-UV: height_scale where the sprite alpha is opaque, else 0.
float sample_height(vec2 uv) {
	vec2 l = to_local(uv);
	if (l.x < 0.0 || l.x > 1.0 || l.y < 0.0 || l.y > 1.0) {
		return 0.0;
	}
	vec2 s = frame_region.xy + clamp(l, vec2(0.0), vec2(1.0)) * frame_region.zw;
	float a = texture(src_tex, s).a;
	return step(alpha_cutoff, a) * height_scale;
}


// March from a ground pixel TOWARD the light; if the rising ray is overtopped by a silhouette pixel, occlude.
float trace(vec2 start_uv, float start_h, vec2 step_uv, float rise, float soft) {
	float occ = 0.0;
	float ray_h = start_h;
	vec2 uv = start_uv;
	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= steps) {
			break;
		}
		uv -= step_uv;
		ray_h += rise;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		float h = sample_height(uv);
		occ = max(occ, smoothstep(0.0, soft, h - ray_h));
		if (occ > 0.999) {
			break;
		}
	}
	return occ;
}


void fragment() {
	float px_to_uv = 1.0 / max(carrier_size_px, 1.0);
	vec2 dir = normalize(sun_dir);
	vec2 step_uv = dir * (step_px * px_to_uv);
	// Ray rise per march step. The ground pixel is in shadow until the rising ray climbs above the silhouette
	// height (height_scale); the sun then "peeks over" the building and the shadow ends. So the shadow LENGTH
	// ≈ height_scale / (0.15 × sun_elevation) px (then capped by steps × step_px): higher elevation ⇒ faster
	// rise ⇒ SHORTER shadow; taller height_scale ⇒ LONGER. The 0.15 keeps that climb-out inside the step budget
	// across the whole elevation slider so it actually bites (0.02 was ~10× too weak → always reach-limited).
	float rise = max(sun_elevation, 1e-3) * (step_px * 0.15);
	float soft = max(shadow_softness, 1e-4);

	float h0 = sample_height(UV);
	vec2 start = UV + dir * (shadow_ray_offset_px * px_to_uv);

	float occ = trace(start, h0, step_uv, rise, soft);
	if (shadow_aa_enabled && shadow_aa_radius_px > 0.0) {
		vec2 perp = vec2(-dir.y, dir.x) * (shadow_aa_radius_px * px_to_uv);
		float o1 = trace(start + perp * 0.5, sample_height(UV + perp * 0.5), step_uv, rise, soft);
		float o2 = trace(start - perp * 0.5, sample_height(UV - perp * 0.5), step_uv, rise, soft);
		float o3 = trace(start + perp * 1.5, sample_height(UV + perp * 1.5), step_uv, rise, soft);
		float o4 = trace(start - perp * 1.5, sample_height(UV - perp * 1.5), step_uv, rise, soft);
		occ = (occ + o1 + o2 + o3 + o4) / 5.0;
	}

	float shadow = shadow_strength * occ;

	vec2 l = to_local(UV);
	bool in_frame = l.x >= 0.0 && l.x <= 1.0 && l.y >= 0.0 && l.y <= 1.0;
	vec4 base = vec4(0.0);
	if (draw_albedo && in_frame) {
		base = texture(src_tex, frame_region.xy + l * frame_region.zw) * COLOR;
	}

	vec4 out_color = vec4(0.0);
	if (base.a > alpha_cutoff) {
		base.rgb = mix(base.rgb, base.rgb * (1.0 - shadow), shadow);
		out_color = base;
	} else {
		out_color = shadow_tint;
		out_color.a *= shadow;
		if (!shadow_on_footprint) {
			out_color.a *= (1.0 - step(alpha_cutoff, h0));   // keep the cast shadow off the building's own footprint
		}
	}
	COLOR = out_color;
}
