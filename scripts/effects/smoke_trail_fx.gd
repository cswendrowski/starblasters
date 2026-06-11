extends Node

# SmokeTrailFx (Roman 2026-06-10) — a soft smoke trail / puff built on a
# GPUParticles2D + ParticleProcessMaterial. Each puff is born light
# (start_color #bfc8c3), fades in, then darkens to end_color (#100c08) as it
# ages and fades out, drifting slowly. Uses a soft procedural puff by default;
# pass `texture` (or drop a sprite at SPRITE_PATH) to use real art.
#
#   SmokeTrailFx.trail(parent, pos, params) -> GPUParticles2D  # continuous
#   SmokeTrailFx.puff(parent, pos, params)  -> GPUParticles2D  # one-shot burst
#
# For a trail behind a moving thing, add the returned emitter as a child of
# that thing (local_coords = false leaves the puffs behind in world space).

# Smoke sprite — a 12-frame strip of a puff billowing then dissipating. Each
# particle plays it once over its life. trail()/puff() use it automatically.
const SPRITE_PATH := "res://graphics/effects/smoke_pulse.png"
const SPRITE_HFRAMES := 12

const START_COLOR := Color(0.749, 0.784, 0.765)  # #bfc8c3 — fresh puff
const END_COLOR := Color(0.063, 0.047, 0.031)    # #100c08 — aged/settled

const DEFAULTS := {
	"amount": 26,
	"lifetime": 1.1,
	"spread_deg": 18.0,
	"angle_deg": -90.0,    # emission direction (−90 = up / behind a rising host)
	"speed_min": 6.0,
	"speed_max": 22.0,
	"gravity": -8.0,       # slight rise
	"damping": 12.0,       # bleed velocity so puffs settle
	"scale_min": 0.5,
	"scale_max": 1.0,
	"scale_grow": 2.4,     # final scale = initial × this
	"spin_deg": 40.0,
	"start_color": START_COLOR,
	"end_color": END_COLOR,
	"peak_alpha": 0.9,
	"texture": null,       # null = sprite at SPRITE_PATH, else procedural puff
	"hframes": 0,          # 0 = auto (SPRITE_HFRAMES for the strip, else 1)
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
	p.name = "SmokeTrail"
	p.amount = maxi(1, int(v["amount"]))
	p.lifetime = float(v["lifetime"])
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.position = pos
	var using_strip: bool = (v["texture"] == null and ResourceLoader.exists(SPRITE_PATH))
	p.texture = _resolve_texture(v["texture"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # soft smoke, not pixel-crisp

	# Sprite-sheet animation: a multi-frame strip plays once over each particle's
	# life (frame 0 at birth → last frame at death) via a CanvasItemMaterial.
	var hf: int = int(v["hframes"])
	if hf <= 0:
		hf = SPRITE_HFRAMES if using_strip else 1
	if hf > 1:
		var cim := CanvasItemMaterial.new()
		cim.particles_animation = true
		cim.particles_anim_h_frames = hf
		cim.particles_anim_v_frames = 1
		cim.particles_anim_loop = false
		p.material = cim

	var m := ParticleProcessMaterial.new()
	if hf > 1:
		m.anim_speed_min = 1.0   # one full strip over the lifetime
		m.anim_speed_max = 1.0
		m.anim_offset_min = 0.0
		m.anim_offset_max = 0.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.5
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
	m.angle_min = -float(v["spin_deg"])
	m.angle_max = float(v["spin_deg"])
	m.angular_velocity_min = -float(v["spin_deg"])
	m.angular_velocity_max = float(v["spin_deg"])
	m.color_ramp = build_ramp(v["start_color"], v["end_color"], float(v["peak_alpha"]))
	p.process_material = m

	parent.add_child(p)
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


# Colour over life: fade in as start_color, hold, then darken to end_color and
# fade out. start/end are the user-facing #bfc8c3 → #100c08.
static func build_ramp(start_c: Color, end_c: Color, peak_a: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(start_c.r, start_c.g, start_c.b, 0.0),
		Color(start_c.r, start_c.g, start_c.b, peak_a),
		Color(end_c.r, end_c.g, end_c.b, peak_a),
		Color(end_c.r, end_c.g, end_c.b, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.78, 1.0])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


static func _resolve_texture(override) -> Texture2D:
	if override != null:
		return override
	if ResourceLoader.exists(SPRITE_PATH):
		return load(SPRITE_PATH)
	return _puff()


# Soft radial puff (32×32) — a neutral smoke particle until real art is dropped.
static func _puff() -> Texture2D:
	if _puff_tex == null:
		var s := 48
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := Vector2(s * 0.5, s * 0.5)
		for y in s:
			for x in s:
				var dd: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
				# Fuller core with a soft feathered edge — reads as a smoke puff.
				var al: float = smoothstep(1.0, 0.35, dd)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, al))
		_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex
