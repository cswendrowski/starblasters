extends Node2D
class_name DamageSmokeTrail

# Damage smoke trail — burning industrial/tech smoke from damaged
# components (Roman/Cody 2026-05-18). Single Line2D with the
# billow_smoke shader applied as a texture, width grows toward the tail
# so the line reads as "dispersing column" rather than a constant-width
# stroke.

const SHADER_PATH := "res://graphics/billow_smoke.gdshader"

const ACTIVATE_BELOW_DEFAULT: float = 0.5  # hull <= 50% → emit (enemy default)
var activate_below: float = ACTIVATE_BELOW_DEFAULT  # lost-hull FRACTION; player passes 0.5 (50% of current max)
# Emission rate scales with damage severity (Roman 2026-05-29): a lightly
# damaged ship puffs slowly + sparsely, a near-dead ship emits at the fast
# rate. Interpolated per hull_changed into _sample_interval.
const SAMPLE_INTERVAL_MIN: float = 0.04   # near death: dense, fast puffs
const SAMPLE_INTERVAL_MAX: float = 0.16   # lightly damaged: sparse puffs
var _sample_interval: float = SAMPLE_INTERVAL_MAX
# Severity easing exponent — must match engine_torch.SEVERITY_EXP so fire
# and smoke ramp together. ROMAN'S TO TUNE. See engine_torch.gd for the
# 3-pip-hull reasoning behind 1.5.
const SEVERITY_EXP: float = 1.5
const MAX_POINTS: int = 56
const POINT_LIFETIME: float = 1.8

# Line width at the head (engine) ramps from MIN_WIDTH at 50% hull to
# MAX_WIDTH at 0% hull (Roman 2026-05-18 "thicker the closer to 0").
const MIN_WIDTH: float = 6.0
const MAX_WIDTH: float = 16.0
# Multiplier at the tail-most point of the curve. 1.0 at head → TAIL_WIDTH_MULT at tail.
# Roman 2026-05-18: bumped to 10× — dramatic flare at the dissipation end.
const TAIL_WIDTH_MULT: float = 10.0

# Drift: older points fall faster (forward-motion left-behind).
# Roman 2026-05-18: +25% over the previous pass.
const DRIFT_BASE_SPEED: float = 225.0
const DRIFT_AGE_GAIN: float = 400.0
# +1.0 = drift downward (player default), -1.0 = drift upward (enemy smoke).
var drift_sign: float = 1.0

# Per-point sideways wander so the column breathes.
const WANDER_PX_PER_SEC: float = 18.0

# Default emit coord (player engine pixel). Bombers / other units pass
# their own via set_player_with_offset() — Roman 2026-05-18.
const EMIT_LOCAL_DEFAULT: Vector2 = Vector2(0, 6)
var emit_local: Vector2 = EMIT_LOCAL_DEFAULT

# Dark industrial palette.
const SMOKE_COLOR := Color(0.10, 0.10, 0.11, 0.90)

var _player: Node2D = null
var _damage_level: float = 0.0
var _severity: float = 0.0   # eased 0..1, drives opacity + emission rate
var _line: Line2D = null
var _sample_t: float = 0.0
var _point_t: Array = []
var _finishing: bool = false   # one-shot guard for the fade-out when the host disappears


func _ready() -> void:
	_line = Line2D.new()
	_line.name = "DamageTrailLine"
	_line.width = MIN_WIDTH
	_line.default_color = SMOKE_COLOR
	# Width curve: thin at head (1.0) → fat at tail (TAIL_WIDTH_MULT).
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, TAIL_WIDTH_MULT))   # tail
	curve.add_point(Vector2(1.0, 1.0))               # head
	_line.width_curve = curve
	# Alpha gradient: head dense at the engine, tail dissipates to 0 even
	# though the WIDTH keeps growing. Combined with width_curve this reads
	# as smoke widening AND fading as it disperses (Roman 2026-05-18).
	# Steeper falloff so the dissipation is obvious — alpha drops fast in
	# the last third of the trail.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.85, 1.0])
	grad.colors = PackedColorArray([
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.35),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.80),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, SMOKE_COLOR.a),
	])
	_line.gradient = grad
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# Smoke draws BELOW the engine fire (torch is at z=1). Set to 0 so the
	# fire stays on top (Roman 2026-05-18).
	_line.z_index = 0
	_line.z_as_relative = false
	# Procedurally-baked noise texture so the strip reads as "smoke" rather
	# than a flat band. Generated once in _build_noise_texture(); tiled
	# along the line's length via Line2D.texture_mode.
	_line.texture = _build_noise_texture()
	_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	# Parent the world-space line into the host's container (same viewport). This
	# node is a child of the host (player), so get_parent() is the host and its
	# parent is the world node. current_scene put it in the HD-root scene when the
	# host lives in a SubViewport → upper-left corner (Roman 2026-06-11; see
	# docs/godot-patterns.md "SubViewport-hosted fx must parent to the host's world").
	var p: Node = null
	if get_parent() != null and get_parent().get_parent() != null:
		p = get_parent().get_parent()
	else:
		p = get_tree().current_scene
	if p == null:
		p = get_tree().root
	p.call_deferred("add_child", _line)


func set_player(player: Node2D) -> void:
	_player = player
	if player.has_signal("hull_changed"):
		if not player.hull_changed.is_connected(_on_hull_changed):
			player.hull_changed.connect(_on_hull_changed)
	if "max_hull" in player and "hull" in player:
		_on_hull_changed(player.max_hull, player.hull)


func _on_hull_changed(max_hull, hull) -> void:
	if max_hull <= 0:
		_damage_level = 0.0
		return
	_damage_level = clamp(1.0 - (float(hull) / float(max_hull)), 0.0, 1.0)
	# Damage severity 0..1 drives width, opacity, and emission rate so the
	# smoke is faint+sparse when lightly damaged and a thick fast column as
	# the ship nears death (Roman 2026-05-29 "scale with severity; light
	# damage = subtle"). Eased (SEVERITY_EXP) over the damaged span so the
	# bottom of the range stays subtle. ROMAN'S TO TUNE: easing exponent +
	# the MIN floors above decide the ramp shape.
	var ramp: float = clamp((_damage_level - activate_below) / (1.0 - activate_below), 0.0, 1.0)
	_severity = pow(ramp, SEVERITY_EXP)
	# Emission rate: slow/sparse when light, fast/dense near death.
	_sample_interval = lerp(SAMPLE_INTERVAL_MAX, SAMPLE_INTERVAL_MIN, _severity)
	if _line and is_instance_valid(_line):
		_line.width = lerp(MIN_WIDTH, MAX_WIDTH, _severity)
		# Opacity scales with severity — was fixed (full-density on the first
		# pip), the binary "worst appearance" Roman flagged. Floor keeps a
		# faint wisp visible once damaged at all.
		_line.modulate.a = lerp(0.15, 1.0, _severity)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		# Host gone (e.g. a wreck hull that exploded / fell off): FADE the trail out over time rather
		# than popping it (Roman 2026-06-10 — "smoke should fade out"). One-shot. The Line2D lives at
		# the scene root (independent of the host), so it survives to finish the tween.
		if not _finishing:
			_finishing = true
			if _line and is_instance_valid(_line):
				var line: Line2D = _line
				_line = null
				var tw := line.create_tween()
				tw.tween_property(line, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_callback(line.queue_free)
			queue_free()
		return
	_age_points(delta)
	if _damage_level < activate_below:
		# Let the existing trail fade out instead of yanking it.
		return
	_sample_t -= delta
	if _sample_t > 0.0:
		return
	_sample_t = _sample_interval
	var pos: Vector2 = _player.to_global(emit_local)
	pos += Vector2(randf_range(-1.5, 1.5), randf_range(-0.5, 0.5))
	_line.add_point(pos)
	_point_t.append(0.0)
	while _line.get_point_count() > MAX_POINTS:
		_line.remove_point(0)
		_point_t.pop_front()


func _age_points(delta: float) -> void:
	if _line == null or not is_instance_valid(_line):
		return
	var n: int = _point_t.size()
	for i in range(n):
		_point_t[i] = float(_point_t[i]) + delta
		var t: float = clamp(float(_point_t[i]) / POINT_LIFETIME, 0.0, 1.0)
		var drop: float = (DRIFT_BASE_SPEED + DRIFT_AGE_GAIN * t) * delta * drift_sign
		var wander: float = WANDER_PX_PER_SEC * delta * sin(float(i) * 0.55 + float(_point_t[i]) * 4.5)
		var p: Vector2 = _line.get_point_position(i)
		_line.set_point_position(i, p + Vector2(wander, drop))
	while _point_t.size() > 0 and float(_point_t[0]) >= POINT_LIFETIME:
		_line.remove_point(0)
		_point_t.pop_front()


func _clear_line() -> void:
	if _line and is_instance_valid(_line):
		_line.clear_points()
	_point_t.clear()


# Build a 128×16 grayscale noise texture (white billows on alpha=0). Tiled
# along the Line2D's length, it modulates the strip's solid color so the
# trail reads as billowy smoke rather than a uniform band.
#
# Roman 2026-06-08: the old texture multiplied sin(x)·cos(y), which is a
# separable grid — it produced regular vertical/horizontal STRIPES with hard
# dark streaks rather than organic smoke. Rebuilt on FastNoiseLite fBm. To kill
# the tiling seam (the texture repeats along the whole trail), the X axis is
# sampled around a CIRCLE in 3D noise space so the left and right edges meet
# seamlessly; Y (across the strip width) is sampled linearly and feathered.
static func _build_noise_texture() -> Texture2D:
	const W: int = 128
	const H: int = 16
	# Loop radius for the seamless X-wrap (bigger = more billows along length).
	const LOOP_RADIUS: float = 3.0
	const Y_SCALE: float = 0.18   # variation across the strip width
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 0xBEEF
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3          # extra octaves = smoother, more detailed billows
	noise.frequency = 1.0              # coords are scaled manually below
	for y in H:
		for x in W:
			# Sample on a circle in (nx, ny) so x=0 and x=W meet without a seam.
			var ang: float = TAU * float(x) / float(W)
			var nx: float = cos(ang) * LOOP_RADIUS
			var ny: float = sin(ang) * LOOP_RADIUS
			var nz: float = float(y) * Y_SCALE
			var n: float = noise.get_noise_3d(nx, ny, nz)   # -1..1
			# Map to 0..1 and lift contrast a touch so billows read as billows,
			# not flat grey, but without the old hard black streaks.
			var base: float = clamp((0.5 + 0.5 * n) * 1.15, 0.0, 1.0)
			# Edges of the strip (top/bottom of texture) feather to 0 so the
			# line's outer pixels are soft rather than hard-cut.
			var v: float = float(y) / float(H - 1)
			var feather: float = 1.0 - pow(abs(v - 0.5) * 2.0, 2.4)
			feather = clamp(feather, 0.0, 1.0)
			var a: float = clamp(base * feather, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
