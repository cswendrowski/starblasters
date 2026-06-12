extends Node

# SmokeTrailFx — a GPUParticles2D smoke trail, REBUILT 2026-06-11 from the canonical Godot 4
# recipe. The old version was thrown out: it leaned on graphics/effects/smoke_pulse.png (a
# near-empty faint-outline strip) animated via CanvasItemMaterial.particles_animation. Because
# color_ramp MULTIPLIES the texture, a faint strip can't be tinted (colours "didn't apply"),
# and the per-frame angle hacks in the emitter never read on the symmetric/empty frames
# (orient / jitter "did nothing"). All of that is gone.
#
# Recipe (matches the Godot docs + the standard smoke tutorials):
#   • PROCEDURAL WHITE billow puff (full opaque coverage) → color_ramp tints it cleanly.
#   • emission from a small sphere; low initial velocity + damping so puffs settle.
#   • scale GROWS over life (scale_curve) → puffs dissipate outward.
#   • color_ramp = two-tone (start across the front half, end across the back half) with an
#     alpha fade-in at birth and fade-out at death.
#   • random initial angle (±180°) + angular_velocity spin → visible tumbling (the puff has
#     billowy lobes, so rotation reads — a perfect circle would not).
#   • local_coords = false → puffs stay in world space, so a moving emitter leaves a trail.
#     smoke_trail_emitter.gd streams the emission BEHIND the host's motion when follow_motion.
#
#   SmokeTrailFx.trail(parent, pos, params) -> GPUParticles2D  # continuous trail
#   SmokeTrailFx.puff(parent, pos, params)  -> GPUParticles2D  # one-shot burst

const EMITTER_SCRIPT := preload("res://scripts/effects/smoke_trail_emitter.gd")

const START_COLOR := Color(0.749, 0.784, 0.765)  # #bfc8c3 — fresh puff
const END_COLOR := Color(0.063, 0.047, 0.031)    # #100c08 — aged/settled

const DEFAULTS := {
	"amount": 26,
	"lifetime": 1.6,
	"spread_deg": 22.0,
	"angle_deg": 0,      # emission direction when NOT following motion (−90 = up)
	"speed_min": 8.0,
	"speed_max": 26.0,
	"gravity": -10.0,        # slight rise
	"damping": 8.0,          # bleed velocity so puffs settle into a trail
	"scale_min": 0.4,
	"scale_max": 0.8,
	"scale_grow": 2.2,       # final scale = initial × this (dissipate outward)
	"spin": 40.0,            # ± angular velocity in deg/s (visible tumble)
	"randomness": 0.5,       # GPUParticles2D randomness — natural variation
	"follow_motion": true,   # stream emission behind the host's velocity
	"start_color": START_COLOR,
	"end_color": END_COLOR,
	"peak_alpha": 0.9,
}

static var _puff_tex: Texture2D = null


static func trail(parent: Node, pos: Vector2, params: Dictionary = {}) -> GPUParticles2D:
	return _make(parent, pos, params, false)


static func puff(parent: Node, pos: Vector2, params: Dictionary = {}) -> GPUParticles2D:
	return _make(parent, pos, params, true)


static func _make(parent: Node, pos: Vector2, params: Dictionary, one_shot: bool) -> GPUParticles2D:
	if parent == null:
		return null
	var v: Dictionary = DEFAULTS.duplicate()
	v.merge(params, true)

	var p := GPUParticles2D.new()
	p.set_script(EMITTER_SCRIPT)
	p.set("follow_motion", bool(v["follow_motion"]))
	p.name = "SmokeTrail"
	p.amount = maxi(1, int(v["amount"]))
	p.lifetime = maxf(0.1, float(v["lifetime"]))
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.randomness = clampf(float(v["randomness"]), 0.0, 1.0)
	p.local_coords = false   # leave puffs behind in world space → the trail
	p.position = pos
	p.texture = _puff()
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # soft smoke, not pixel-crisp

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 2.0
	var a := deg_to_rad(float(v["angle_deg"]))
	m.direction = Vector3(cos(a), sin(a), 0.0)
	m.spread = float(v["spread_deg"])
	m.initial_velocity_min = float(v["speed_min"])
	m.initial_velocity_max = float(v["speed_max"])
	m.gravity = Vector3(0.0, float(v["gravity"]), 0.0)
	m.damping_min = float(v["damping"])
	m.damping_max = float(v["damping"])
	m.scale_min = float(v["scale_min"])
	m.scale_max = float(v["scale_max"])
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, float(v["scale_grow"])))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	# Random initial rotation + a gentle continuous tumble — the canonical smoke rotation.
	# Visible because the puff has billowy lobes (a perfect circle would hide it).
	m.angle_min = -180.0
	m.angle_max = 180.0
	var spin: float = float(v["spin"])
	m.angular_velocity_min = -spin
	m.angular_velocity_max = spin
	m.color_ramp = build_ramp(v["start_color"], v["end_color"], float(v["peak_alpha"]))
	p.process_material = m

	parent.add_child(p)
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


# Colour over life — a TWO-TONE trail: the front ~half holds start_color, the back ~half
# holds end_color, with a short cross-fade at mid-life (Roman 2026-06-11: the second colour
# should occupy ~half the string). Alpha fades in at birth + out at death. Multiplies the
# WHITE puff, so the tints land exactly as picked. start/end = #bfc8c3 → #100c08 (tunable).
static func build_ramp(start_c: Color, end_c: Color, peak_a: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(start_c.r, start_c.g, start_c.b, 0.0),    # 0.00 birth — transparent
		Color(start_c.r, start_c.g, start_c.b, peak_a), # 0.06 fade-in done
		Color(start_c.r, start_c.g, start_c.b, peak_a), # 0.38 hold start (front half)
		Color(end_c.r, end_c.g, end_c.b, peak_a),       # 0.52 cross-faded to end
		Color(end_c.r, end_c.g, end_c.b, peak_a),       # 0.92 hold end (back half)
		Color(end_c.r, end_c.g, end_c.b, 0.0),          # 1.00 death — transparent
	])
	g.offsets = PackedFloat32Array([0.0, 0.06, 0.38, 0.52, 0.92, 1.0])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


# Procedural billow puff (64×64): a few overlapping soft lobes → an irregular WHITE puff.
# Full white so color_ramp tints it; the lobes give it asymmetry so rotation/tumble reads.
static func _puff() -> Texture2D:
	if _puff_tex == null:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var lobes := [
			{"c": Vector2(0.50, 0.50), "r": 0.40},
			{"c": Vector2(0.37, 0.44), "r": 0.28},
			{"c": Vector2(0.63, 0.47), "r": 0.27},
			{"c": Vector2(0.52, 0.64), "r": 0.30},
		]
		for y in s:
			for x in s:
				var uv := Vector2((x + 0.5) / float(s), (y + 0.5) / float(s))
				var al: float = 0.0
				for lobe in lobes:
					var d: float = uv.distance_to(lobe["c"]) / float(lobe["r"])
					al = maxf(al, smoothstep(1.0, 0.2, d))
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, al))
		_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex
