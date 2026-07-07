extends "res://scripts/enemies/enemy_core.gd"

# Abductor (Roman 2026-07-06) — supremacy small hull with a gravity GRAB BEAM. Once the player crosses
# into grab_range it LATCHES on and leashes them: the player moves freely within leash_distance, but is
# reeled back whenever they try to pull farther — so as the abductor drifts, it hauls the player along,
# "preventing the player from getting too far." The grab holds until the abductor is DESTROYED (or leaves
# the field), which frees the player. Only the player is grabbed. The beam is the tether-mine's squiggly
# gravity line (#c73bff), drawn from the MuzzleGravity marker.

@export var grab_range: float = 130.0      # player distance that triggers the latch
@export var leash_distance: float = 78.0   # max distance the player may get from the abductor
@export var pull_lerp: float = 0.35        # how hard to reel the player back toward the leash edge
@export var max_pull_px: float = 8.0       # per-physics-step reel cap — a steady drag, not a yank

const BEAM_COLOR := Color(0.78, 0.231, 1.0, 0.95)   # #c73bff gravity
const BEAM_AMPLITUDE_PX := 5.0
const BEAM_FREQUENCY := 8.0
const BEAM_SEGMENTS := 24
const BEAM_WIDTH := 2.0

var _grabbed: bool = false
var _beam_t: float = 0.0
var _muzzle: Node2D = null


func _ready() -> void:
	if max_health <= 1:
		max_health = 3
	if bounty_value <= 0:
		bounty_value = 15
	auto_rotate = false   # a fixed facing keeps the beam + sprite steady while it leashes
	super._ready()
	_muzzle = get_node_or_null("MuzzleGravity")


func _process(delta: float) -> void:
	super._process(delta)   # movement + component ticks (enemy_core)
	if _dying:
		return
	var pl := find_player()
	if pl == null or not is_instance_valid(pl):
		return
	if not _grabbed and global_position.distance_to((pl as Node2D).global_position) <= grab_range:
		_grabbed = true
	if _grabbed:
		_beam_t += delta
		queue_redraw()


func _physics_process(delta: float) -> void:
	if not _grabbed or _dying:
		return
	var pl := find_player()
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		return
	var pn := pl as Node2D
	var to_ab: Vector2 = global_position - pn.global_position
	var dist: float = to_ab.length()
	if dist <= leash_distance:
		return   # inside the leash → free movement
	# Beyond the leash → reel the player back toward the leash edge. Capped + lerped so it fights player
	# input as a steady drag rather than a teleport (matches the tether mine's smoothing).
	var overshoot: float = dist - leash_distance
	var reel: Vector2 = to_ab.normalized() * minf(overshoot, max_pull_px)
	pn.global_position = pn.global_position.lerp(pn.global_position + reel, pull_lerp)


func explode() -> void:
	# Killing the abductor frees the player (the leash stops the instant _grabbed clears).
	_grabbed = false
	queue_redraw()
	super.explode()


func _beam_origin() -> Vector2:
	return _muzzle.global_position if (_muzzle != null and is_instance_valid(_muzzle)) else global_position


func _draw() -> void:
	if not _grabbed or _dying:
		return
	var pl := find_player()
	if pl == null or not (pl is Node2D):
		return
	var origin_local: Vector2 = to_local(_beam_origin())
	var seg: Vector2 = to_local((pl as Node2D).global_position) - origin_local
	var length: float = seg.length()
	if length < 1.0:
		return
	var dir: Vector2 = seg / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var points := PackedVector2Array()
	for i in range(BEAM_SEGMENTS + 1):
		var u: float = float(i) / float(BEAM_SEGMENTS)
		var taper: float = sin(u * PI)   # taper the squiggle to attach cleanly at both ends
		var amp: float = sin(_beam_t * BEAM_FREQUENCY + float(i) * 0.6) * BEAM_AMPLITUDE_PX * taper
		points.push_back(origin_local + dir * (length * u) + perp * amp)
	draw_polyline(points, Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.28), BEAM_WIDTH * 3.0)
	draw_polyline(points, Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.5), BEAM_WIDTH * 1.8)
	draw_polyline(points, BEAM_COLOR, BEAM_WIDTH)
