extends "res://scripts/enemies/enemy_core.gd"

# Abductor (Roman 2026-07-06) — supremacy small hull with a gravity GRAB BEAM. Once the player crosses
# into grab_range it LATCHES on and leashes them: the player moves freely within leash_distance, but is
# reeled back whenever they try to pull farther — so as the abductor drifts, it hauls the player along,
# "preventing the player from getting too far." The grab holds until the abductor is DESTROYED (or leaves
# the field), which frees the player. Only the player is grabbed. The beam is the tether-mine's squiggly
# gravity line (#c73bff), drawn from the MuzzleGravity marker.

@export var grab_range: float = 130.0      # player distance that triggers the latch
@export var leash_distance: float = 78.0   # max distance the player may get from the abductor

# --- Spring pull tuning (Roman 2026-07-07). The player runs the actual spring physics
# (apply_external_pull) so authority stays player-side; these are the knobs we hand it. ---
@export var pull_spring: float = 14.0      # spring stiffness — accel toward the leash edge per px of error
@export var pull_damping: float = 6.0      # velocity bleed (higher = calmer, less overshoot)
@export var pull_max_speed: float = 260.0  # px/s ceiling on the tractor drag

# --- Tether-break-under-stress tuning (Roman 2026-07-07). Two ways the leash snaps:
#   1) HARD stretch — the player yanks past leash_distance + break_stretch (a fast escape wins outright).
#   2) STRESS accrual — sustained fighting (stretched past the leash while thrusting AWAY) builds stress;
#      when it crosses break_stress the tether pops. Stress relaxes when the player stops fighting. ---
@export var break_stretch: float = 46.0    # px past the leash edge that snaps the tether outright
@export var break_stress: float = 1.0      # accumulated stress (0..1-ish) at which the tether breaks
@export var stress_gain: float = 1.4       # stress/sec built while stretched + thrusting away
@export var stress_relax: float = 2.2      # stress/sec bled off when not actively fighting
@export var regrab_cooldown: float = 1.1   # seconds after a break before it can latch again

const BEAM_COLOR := Color(0.78, 0.231, 1.0, 0.95)   # #c73bff gravity
const BEAM_AMPLITUDE_PX := 5.0
const BEAM_FREQUENCY := 8.0
const BEAM_SEGMENTS := 24
const BEAM_WIDTH := 2.0

var _grabbed: bool = false
var _beam_t: float = 0.0
var _muzzle: Node2D = null
var _stress: float = 0.0        # accumulated tether stress (0 = slack)
var _regrab_lock_t: float = 0.0 # seconds remaining before a broken tether may re-latch


func _ready() -> void:
	# Stats come from the roster (small size → hp 4); the .tscn carries the same default for
	# raw bench/dev spawns. No silent <=1 backfill here (the banned default pattern — boss 1-HP bug).
	if bounty_value <= 0:
		bounty_value = 15
	# auto_rotate stays ON (default) so the omni hull turns to face the player — muzzle (front) toward the
	# grab target, engines trailing (Roman 2026-07-08 facing fix; was false, which froze the facing and
	# left it pointing away while moving). The gravity beam is redrawn every frame in local space, so a
	# rotating hull is fine — it just keeps the beam attached to the muzzle marker.
	super._ready()
	_muzzle = get_node_or_null("MuzzleGravity")


func _process(delta: float) -> void:
	super._process(delta)   # movement + component ticks (enemy_core)
	if _dying:
		return
	_tick_grab_state(delta)


# Grab-state tick — extracted from _process so it can be exercised headless. Ticks the re-grab
# cooldown, gates on the recycle (non-combatant) state, and latches when the player enters range.
func _tick_grab_state(delta: float) -> void:
	if _regrab_lock_t > 0.0:
		_regrab_lock_t = maxf(0.0, _regrab_lock_t - delta)
	# Recycling / offscreen fly-back = non-combatant (RecycleController-owned ghost state). Never
	# engage the beam, and force-release if a grab was live when the recycle pass started.
	if is_recycling():
		if _grabbed:
			_release_beam(false)
		return
	var pl := find_player()
	if pl == null or not is_instance_valid(pl):
		return
	if not _grabbed and _regrab_lock_t <= 0.0 and global_position.distance_to((pl as Node2D).global_position) <= grab_range:
		_grabbed = true
		_stress = 0.0
	if _grabbed:
		_beam_t += delta
		queue_redraw()


func _physics_process(delta: float) -> void:
	if not _grabbed or _dying or is_recycling():
		return
	_tick_reel(delta)


# Reel/stress tick — extracted from _physics_process so it can be exercised headless. Runs the
# tether stress/break model, then (if still grabbed + stretched) hands the player a spring anchor.
func _tick_reel(delta: float) -> void:
	var pl := find_player()
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		return
	var pn := pl as Node2D
	var to_ab: Vector2 = global_position - pn.global_position
	var dist: float = to_ab.length()
	var dir: Vector2 = to_ab / dist if dist > 0.001 else Vector2.ZERO
	var overshoot: float = dist - leash_distance

	# --- Tether stress / break ---------------------------------------------------------
	# Hard snap: yanked clean past the leash + break margin (a decisive escape always wins).
	if overshoot > break_stretch:
		_release_beam(true)
		return
	# Stress accrues while stretched AND the player is thrusting AWAY from the abductor (fighting the
	# reel). Otherwise it relaxes. `_move_velocity` is the player's per-frame input velocity (px/s).
	var fighting: bool = false
	if overshoot > 0.0 and ("_move_velocity" in pn):
		var pv: Vector2 = pn._move_velocity
		# Away = same direction the player is being pulled FROM (opposite of dir, which points to abductor).
		if pv.length() > 1.0 and pv.normalized().dot(-dir) > 0.35:
			fighting = true
	if fighting:
		_stress += stress_gain * delta
	else:
		_stress = maxf(0.0, _stress - stress_relax * delta)
	if _stress >= break_stress:
		_release_beam(true)
		return

	if dist <= leash_distance:
		return   # inside the leash → free movement, no reel this frame

	# Beyond the leash → hand the player a WORLD-SPACE anchor at the leash edge and let it run a
	# damped spring toward it (player-side authority, mirrors the ram knockback). The spring gives the
	# drag inertia/mass instead of the old rigid position-lerp.
	var anchor: Vector2 = global_position - dir * leash_distance
	if pn.has_method("apply_external_pull"):
		pn.apply_external_pull(anchor, delta, pull_spring, pull_damping, pull_max_speed)


func explode() -> void:
	# Killing the abductor frees the player (the leash stops the instant _grabbed clears).
	_release_beam(false)
	super.explode()


# Single release/teardown path — used on tether break, recycle, and death. Clears the grab, resets the
# stress accumulator, and tears down the beam visual (it only draws while _grabbed, so the queue_redraw
# clears it). `arm_cooldown` starts the re-grab lock so a broken tether can't instantly re-latch.
func _release_beam(arm_cooldown: bool) -> void:
	if not _grabbed and not arm_cooldown:
		return
	_grabbed = false
	_stress = 0.0
	if arm_cooldown:
		_regrab_lock_t = regrab_cooldown
	queue_redraw()


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
