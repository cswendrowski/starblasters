extends Node2D
class_name MissileSmokeTrail

# Light-gray smoke trail for player missiles + rockets. Copy of the
# damage_smoke_trail aesthetic (Cobalt 2026-05-21), retuned for ordnance:
#   - Always emits while attached (no hull threshold)
#   - Light gray instead of black
#   - Smaller width than the player damage trail; missiles are tinier
#     than ships, so a 16-px stripe behind a 16-px sprite is overkill

const SAMPLE_INTERVAL: float = 0.04
const MAX_POINTS: int = 32
const POINT_LIFETIME: float = 1.2

const HEAD_WIDTH: float = 3.0
const TAIL_WIDTH_MULT: float = 6.0

const DRIFT_BASE_SPEED: float = 180.0
const DRIFT_AGE_GAIN: float = 320.0
const WANDER_PX_PER_SEC: float = 12.0

# Light gray (Cobalt 2026-05-21: copy of damage smoke recoloured from
# black to light gray).
const SMOKE_COLOR := Color(0.78, 0.78, 0.80, 0.85)

# Set true on downward-traveling rockets so the drift trails BEHIND (upward)
# instead of forward (downward). Player missiles leave this false.
var flip_drift: bool = false

var _emitter: Node2D = null
var _line: Line2D = null
var _sample_t: float = 0.0
var _point_t: Array = []


func _ready() -> void:
	_line = Line2D.new()
	_line.name = "MissileTrailLine"
	_line.width = HEAD_WIDTH
	_line.default_color = SMOKE_COLOR
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, TAIL_WIDTH_MULT))
	curve.add_point(Vector2(1.0, 1.0))
	_line.width_curve = curve
	# Head transparent so the 3-px wide trail doesn't sit on top of the
	# 4x8-px missile sprite (Cody 2026-05-24 playtest: rockets/missiles
	# "missing their projectiles/sprites" — the z=3 trail was occluding
	# the z=-1 missile sprite). Smoke fades IN behind the warhead, peaks
	# mid-trail, then dissipates at the tail.
	# Point 0 = oldest (tail), last point = newest (head/missile position).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 0.85, 1.0])
	grad.colors = PackedColorArray([
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0),       # tail dispersed
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.55),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, SMOKE_COLOR.a),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.45),
		Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0),       # head transparent (missile visible)
	])
	_line.gradient = grad
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = 3
	_line.z_as_relative = false
	_line.texture = _build_noise_texture()
	_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	var p := get_tree().current_scene
	if p == null:
		p = get_tree().root
	p.call_deferred("add_child", _line)


func attach_to(emitter: Node2D) -> void:
	_emitter = emitter


func _process(delta: float) -> void:
	if _emitter == null or not is_instance_valid(_emitter):
		_fade_out()
		return
	_age_points(delta)
	_sample_t -= delta
	if _sample_t > 0.0:
		return
	_sample_t = SAMPLE_INTERVAL
	if _line == null or not is_instance_valid(_line):
		return
	var pos: Vector2 = _emitter.global_position + Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5))
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
		var drop: float = (DRIFT_BASE_SPEED + DRIFT_AGE_GAIN * t) * delta
		if flip_drift:
			drop = -drop  # downward rockets: trail drifts upward (behind the rocket)
		var wander: float = WANDER_PX_PER_SEC * delta * sin(float(i) * 0.55 + float(_point_t[i]) * 4.5)
		var p: Vector2 = _line.get_point_position(i)
		_line.set_point_position(i, p + Vector2(wander, drop))
	while _point_t.size() > 0 and float(_point_t[0]) >= POINT_LIFETIME:
		_line.remove_point(0)
		_point_t.pop_front()


# Tween the line's alpha to 0 then free it. Called when the missile
# explodes / leaves the playfield so the trail dissipates naturally
# instead of getting yanked.
func _fade_out() -> void:
	if _line and is_instance_valid(_line):
		var line: Line2D = _line
		_line = null
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(line.queue_free)


# The line lives in the SCENE (not under this node), so when this trail node is freed
# with its host (a despawned shredder pellet / missile) the line would otherwise be
# orphaned and persist forever (Roman 2026-06-11: "shredder smoke stacks infinitely").
# Fade + free it on exit.
func _exit_tree() -> void:
	_fade_out()


static func _build_noise_texture() -> Texture2D:
	const W: int = 64
	const H: int = 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xABCD
	for y in H:
		for x in W:
			var base: float = 0.6 + 0.4 * sin(float(x) * 0.35) * cos(float(y) * 0.6)
			var grain: float = rng.randf_range(0.6, 1.0)
			var v: float = float(y) / float(H - 1)
			var feather: float = 1.0 - pow(abs(v - 0.5) * 2.0, 2.4)
			feather = clamp(feather, 0.0, 1.0)
			var a: float = clamp(base * grain * feather, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
