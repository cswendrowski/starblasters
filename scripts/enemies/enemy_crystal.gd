extends "res://scripts/enemy_core.gd"

# Crystal (Roman, 2026-05-24): custom 6-phase state machine. Dives to
# the lower playfield, fishtails to a stop while aiming at the player,
# fires, climbs back to the top, fishtails again, fires. After each
# full loop a 50/50 coin flip decides whether to repeat or commit to a
# straight-down exit. Owns its own rotation (auto_rotate = false) so
# the fishtail aim doesn't fight EnemyBase's velocity-based banking.
#
# The host's shoot_pattern (spread5 by default) drives the actual
# bullet emission — we just call `shoot_pattern.fire(self)` at the
# FIRE_* states. Movement Resource on the enemy is ignored: `start()`
# below skips the pattern bind so wave-gen's loiter override is inert.

enum Phase {
	DIVE_DOWN,
	FISHTAIL_STOP_LOW,
	FIRE_LOW,
	RISE_UP,
	FISHTAIL_STOP_HIGH,
	FIRE_HIGH,
	EXITING,
}

# Tuning. Numbers in the brief's prose; tightened a hair so the stop
# is unambiguous and the fire-then-go transition reads.
const TARGET_Y_LOW: float = 200.0
const TARGET_Y_HIGH: float = 30.0
const DIVE_SPEED: float = 220.0       # px/s when far from target
const SLOW_BAND: float = 30.0         # last 30 px decelerate (brief)
const SLOW_MIN_SPEED: float = 35.0    # don't crawl to literal 0 mid-band
const FISHTAIL_TIME: float = 0.4      # brief: ~0.4s decel + rotate
const ROT_LERP_RATE: float = 8.0      # rad/s lerp factor for aim turn
const FIRE_PAUSE: float = 0.18        # brief delay so the fire frame reads
const EXIT_SPEED: float = 260.0       # final straight-down exit speed

var _phase: int = Phase.DIVE_DOWN
var _phase_t: float = 0.0
var _fired_this_phase: bool = false
var _aim_rotation: float = PI         # default = facing down (sprite up = -Y → rot=PI faces +Y)


func _ready() -> void:
	# Brief is explicit: auto_rotate = false. Crystal owns its
	# orientation via the fishtail aim logic. Setting this BEFORE
	# super._ready() means enemy_base skips the velocity-bank AND the
	# engine-flame/damage-overlay attach (both gated on auto_rotate).
	# Roman's call: shed the flame in exchange for clean aim control.
	auto_rotate = false
	super._ready()


func start(pos: Vector2) -> void:
	# Skip enemy_core's pattern bind + anchor bind. Crystal owns its
	# own motion via _process. Wave-gen's `movement` (loiter) is left
	# attached on the property but never instantiated into `_pattern`.
	position = pos
	_phase = Phase.DIVE_DOWN
	_phase_t = 0.0
	_fired_this_phase = false
	# Spawn rotation = facing down toward the player.
	_aim_rotation = PI
	rotation = _aim_rotation
	if shoot_pattern != null and has_node("ShootTimer"):
		# We don't actually use ShootTimer — we fire directly at FIRE_*
		# phases. Stop the timer so it doesn't double-fire over the
		# state machine.
		$ShootTimer.stop()


# Crystal owns rotation. Override the base's velocity-bank so the
# fishtail aim isn't fought every frame.
func _apply_auto_rotation() -> void:
	pass


func _process(delta: float) -> void:
	# Skip enemy_core's pattern-driven _process entirely.
	if _dying:
		return
	var safe_delta: float = min(delta, 1.0 / 30.0)
	match _phase:
		Phase.DIVE_DOWN:
			_run_dive(safe_delta, TARGET_Y_LOW)
		Phase.FISHTAIL_STOP_LOW:
			_run_fishtail(safe_delta, Phase.FIRE_LOW)
		Phase.FIRE_LOW:
			_run_fire(safe_delta, Phase.RISE_UP)
		Phase.RISE_UP:
			_run_dive(safe_delta, TARGET_Y_HIGH)
		Phase.FISHTAIL_STOP_HIGH:
			_run_fishtail(safe_delta, Phase.FIRE_HIGH)
		Phase.FIRE_HIGH:
			# Same as FIRE_LOW but on completion does the 50/50 decision.
			_run_fire(safe_delta, -1)
		Phase.EXITING:
			position.y += EXIT_SPEED * safe_delta
			# Defer to the base's offscreen cleanup so the enemy is
			# removed on bottom exit (no parallax cycle).
			_offscreen_cleanup_check()


func _run_dive(delta: float, target_y: float) -> void:
	var dy: float = target_y - position.y
	var dist: float = abs(dy)
	if dist <= 1.5:
		# Reached the target band. Enter the fishtail.
		position.y = target_y
		_phase_t = 0.0
		if _phase == Phase.DIVE_DOWN:
			_phase = Phase.FISHTAIL_STOP_LOW
		else:
			_phase = Phase.FISHTAIL_STOP_HIGH
		return
	# Slow down inside the last SLOW_BAND px so the arrival eases.
	var speed_now: float = DIVE_SPEED
	if dist < SLOW_BAND:
		var t: float = dist / SLOW_BAND  # 1.0 at edge of band → 0 at target
		speed_now = lerp(SLOW_MIN_SPEED, DIVE_SPEED, t)
	var dir: float = signf(dy)
	position.y += dir * speed_now * delta
	# Keep facing the travel direction during dive — visual continuity.
	# We tween the aim toward this so the transition into FISHTAIL is
	# smooth.
	var travel_rot: float = PI if dir > 0.0 else 0.0
	rotation = lerp_angle(rotation, travel_rot, ROT_LERP_RATE * delta)
	_aim_rotation = rotation


func _run_fishtail(delta: float, next_phase: int) -> void:
	_phase_t += delta
	# Aim rotation toward the player. Sprite's "up" is -Y at rotation=0,
	# so rotation = atan2(dy, dx) + PI/2 points the sprite at (dx, dy).
	var target_rot: float = rotation
	var p := find_player()
	if p != null:
		var to_p: Vector2 = p.global_position - global_position
		if to_p.length_squared() > 1.0:
			target_rot = to_p.angle() + PI * 0.5
	rotation = lerp_angle(rotation, target_rot, ROT_LERP_RATE * delta)
	_aim_rotation = rotation
	# Decelerate (we don't carry velocity into the fishtail — _run_dive
	# stops snap-to-target on arrival — but the brief calls for ~0.4s of
	# settle so the player has a moment to read the aim before the shot).
	if _phase_t >= FISHTAIL_TIME:
		_phase_t = 0.0
		_fired_this_phase = false
		_phase = next_phase


func _run_fire(delta: float, after_phase: int) -> void:
	_phase_t += delta
	# Fire once at the very start of the phase, then sit for FIRE_PAUSE
	# so the muzzle is visibly attached to the stopped sprite.
	if not _fired_this_phase:
		_fired_this_phase = true
		if shoot_pattern != null:
			shoot_pattern.fire(self)
		if has_node("EnemyShoot"):
			$EnemyShoot.play()
	if _phase_t >= FIRE_PAUSE:
		_phase_t = 0.0
		_fired_this_phase = false
		if after_phase >= 0:
			_phase = after_phase
		else:
			# End of one full loop. 50/50: repeat or exit.
			if randf() < 0.5:
				_phase = Phase.DIVE_DOWN
			else:
				_phase = Phase.EXITING
				# Face down for the final exit.
				rotation = PI


# Crystal never parallax-cycles — when it commits to EXITING we want a
# straight free, not a fly-back. Override the cycle hook.
func _on_offscreen() -> void:
	_leave()


# Crystal sits inside the playfield band; the base's CYCLE_BOTTOM mode
# would only trigger on a bottom exit. During the EXITING phase that's
# exactly what we want, so we keep the default offscreen_mode and just
# rely on the _process EXITING branch to call _offscreen_cleanup_check.
# (The base's own _process is shadowed by our override, so we have to
# pump cleanup ourselves during EXITING.)
