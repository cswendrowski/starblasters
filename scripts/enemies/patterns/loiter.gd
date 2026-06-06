extends "res://scripts/enemies/movement_pattern.gd"

# Holder (m6 §13). Enter from the top, ease IN (accel from a slow start up to a
# cruise speed) then ease OUT (decelerate to a hold) at hover_y, hold for
# `loiter_time` with a gentle bob/sway so it reads as ALIVE (not frozen), then
# accelerate away downward. Three placement variants (low/mid/high) ride the same
# pattern via hover_y — see EnemyRoster make_movement loiter_{low,mid,high}.
#
# Pattern pass 2026-06-05 (Roman): hold-jiggle ("like bombers"), true ease-IN, the
# low/mid/high band; 06-06: the jiggle is RANDOMIZED per instance (phase + slight
# frequency jitter) so a ROW of Holders desyncs instead of bobbing in lockstep.
# (Each enemy_core enemy gets its own duplicated _pattern, so randf() in on_start
# is independent per ship.) The hold uses absolute repositioning (target = anchor +
# offset) so it can't accumulate drift.

# Hold position. Clamped to the top half (<= 135) so the Holder never settles in
# the player's lap. Variants: high ~50, mid ~90, low ~130.
@export var hover_y: float = 88.0
@export var enter_speed: float = 60.0          # cruise speed during entry
@export var loiter_time: float = 3.0
@export var exit_accel: float = 300.0
@export var exit_max_speed: float = 280.0

# Entry easing. accel ramps from a slow start up to enter_speed; decel slows the
# approach over the last `decel_dist` px into hover_y. Both give a weighted feel.
@export var enter_accel: float = 180.0
@export var enter_decel: float = 220.0
@export var decel_dist: float = 40.0
# Floor for the eased approach speed so a SHORT entry (e.g. the high variant, only
# ~38px to hover_y — under decel_dist) still arrives crisply instead of crawling in
# at a few px/s. Without this the arrival speed ~= the bob speed and the jiggle
# reads as a slow drift, not a distinct settle-then-bob. (Roman 06-06: "high
# doesn't have its jiggle".) Same Zeno guard the Skirmisher uses.
@export var enter_min_speed: float = 40.0

# Hold-jiggle: a small bob (vertical) + sway (horizontal) so the hold reads alive.
# Kept tiny so the Holder stays in its lane and remains shootable.
@export var jiggle_amp_y: float = 3.0
@export var jiggle_freq_y: float = 0.6         # Hz
@export var jiggle_amp_x: float = 2.0
@export var jiggle_freq_x: float = 0.35        # Hz

signal phase_entered(phase_name: String)

enum Phase { ENTERING, LOITERING, EXITING }
var _phase: int = Phase.ENTERING
var _timer: float = 0.0
var _exit_speed: float = 0.0
var _enter_vel: float = 0.0   # current downward velocity during ENTERING
var _hold_t: float = 0.0      # time spent in LOITERING (drives the jiggle)
var _anchor: Vector2 = Vector2.ZERO   # hold center (captured on hold entry)
# Per-instance jiggle randomization (set in on_start; independent per dup).
var _phase_x: float = 0.0
var _phase_y: float = 0.0
var _freq_mul_x: float = 1.0
var _freq_mul_y: float = 1.0


func on_start(enemy) -> void:
	_phase = Phase.ENTERING
	_timer = 0.0
	_exit_speed = 0.0
	# Ease IN: start at a fraction of cruise and accelerate up (not a hard pop-in).
	_enter_vel = enter_speed * 0.3
	_hold_t = 0.0
	# Clamp hover_y so the enemy never settles in the bottom half (y > 135).
	hover_y = minf(hover_y, 135.0)
	# Randomize the jiggle so a row of Holders doesn't bob in lockstep.
	_phase_x = randf() * TAU
	_phase_y = randf() * TAU
	_freq_mul_x = randf_range(0.8, 1.2)
	_freq_mul_y = randf_range(0.85, 1.15)
	phase_entered.emit("enter")


# Absolute jiggle offset, centered so it is exactly (0,0) at _hold_t == 0 (no pop
# on hold entry, no drift over time).
func _jiggle_off(t: float) -> Vector2:
	var oy: float = jiggle_amp_y * (sin(t * jiggle_freq_y * _freq_mul_y * TAU + _phase_y) - sin(_phase_y))
	var ox: float = jiggle_amp_x * (sin(t * jiggle_freq_x * _freq_mul_x * TAU + _phase_x) - sin(_phase_x))
	return Vector2(ox, oy)


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTERING:
			var dist: float = hover_y - enemy.position.y
			if dist <= 0.0:
				# Arrived or overshot — snap to hover_y and hold.
				var snap: float = hover_y - enemy.position.y
				_enter_hold(enemy)
				return Vector2(0, snap)
			# Far → accelerate toward cruise; near → decelerate for the approach.
			# Floored so a short entry arrives crisply (see enter_min_speed).
			var target_vel: float = maxf(enter_speed * clampf(dist / decel_dist, 0.0, 1.0), enter_min_speed)
			var rate: float = enter_accel if target_vel > _enter_vel else enter_decel
			_enter_vel = move_toward(_enter_vel, target_vel, rate * delta)
			_enter_vel = maxf(_enter_vel, 0.0)
			var step: float = _enter_vel * delta
			if enemy.position.y + step >= hover_y:
				step = hover_y - enemy.position.y
				_enter_hold(enemy)
			return Vector2(0, step)
		Phase.LOITERING:
			_timer += delta
			_hold_t += delta
			if _timer >= loiter_time:
				_phase = Phase.EXITING
				_exit_speed = enter_speed
				phase_entered.emit("exit")
				# Return to the anchor cleanly so the exit starts from hover_y.
				return _anchor - enemy.position
			# Absolute repositioning: position = anchor + jiggle offset.
			return (_anchor + _jiggle_off(_hold_t)) - enemy.position
		Phase.EXITING:
			_exit_speed = min(_exit_speed + exit_accel * delta, exit_max_speed)
			return Vector2(0, _exit_speed * delta)
	return Vector2.ZERO


func _enter_hold(enemy) -> void:
	_phase = Phase.LOITERING
	_timer = 0.0
	_hold_t = 0.0
	_enter_vel = 0.0
	# Anchor = where the ship ends up THIS frame (x unchanged, y snapped to hover_y).
	_anchor = Vector2(enemy.position.x, hover_y)
	phase_entered.emit("hold")
