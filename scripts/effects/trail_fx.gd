extends Node

# Particle trail helper. Builds a single GPUParticles2D behind a moving Node2D
# (bullet) to leave a glowing dot trail. Designed to run on the project's
# `gl_compatibility` renderer, which does NOT support GPUParticles2D
# sub-emitters or `emit_subparticle()`. So instead of the godotshaders "zero-
# gap" sub-emitter dance, this emits at a high steady rate from a single
# emitter with `local_coords = false` so dots stay put as the bullet flies on.
# At amount/lifetime = 64/0.4 the spacing at -1400 px/s is ~9px — visually
# continuous when paired with the soft 16px dot texture rendered at scale 6.

# Cached shared resources — built once across all bullets.
static var _dot_tex: GradientTexture2D = null
static var _player_mat: ParticleProcessMaterial = null
static var _enemy_mat: ParticleProcessMaterial = null

static func _ensure_resources() -> void:
	if _dot_tex == null:
		# Soft radial dot: bright core fading to transparent.
		var grad = Gradient.new()
		grad.colors = PackedColorArray([
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 0.6),
			Color(1, 1, 1, 0.0),
		])
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = grad
		_dot_tex.width = 16
		_dot_tex.height = 16
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)

	if _player_mat == null:
		_player_mat = _build_material(Color(0.55, 0.9, 1.0, 0.7))
	if _enemy_mat == null:
		_enemy_mat = _build_material(Color(1.0, 0.45, 0.25, 0.7))

static func _build_material(tint: Color) -> ParticleProcessMaterial:
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	m.direction = Vector3(0, 0, 0)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	m.gravity = Vector3.ZERO
	m.scale_min = 0.6
	m.scale_max = 1.0
	# Shrink to zero across particle lifetime.
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex = CurveTexture.new()
	scale_tex.curve = scale_curve
	m.scale_curve = scale_tex
	# Color ramp: bright at birth -> faded out.
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, tint.a),
		Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var color_ramp = GradientTexture1D.new()
	color_ramp.gradient = grad
	color_ramp.width = 32
	m.color_ramp = color_ramp
	return m

# Attaches a trail to `host` (a Node2D). is_player toggles the color palette.
static func attach_trail(host: Node2D, is_player: bool = true) -> void:
	if host == null or not is_instance_valid(host):
		return
	_ensure_resources()
	var p = GPUParticles2D.new()
	p.name = "Trail"
	p.amount = 64
	p.lifetime = 0.4
	p.one_shot = false
	p.explosiveness = 0.0
	# World-space so particles stay where they were emitted as the bullet moves.
	p.local_coords = false
	p.process_material = _player_mat if is_player else _enemy_mat
	p.texture = _dot_tex
	# All gameplay sprites at 1x (Roman, 2026-05-17); trail dots match.
	p.scale = Vector2(1, 1)
	p.emitting = true
	host.add_child(p)
