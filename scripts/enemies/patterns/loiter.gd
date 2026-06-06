extends "res://scripts/enemies/movement_pattern.gd"

# Holder (m6 §13). Enter from the top, ease IN (accel from a slow start up to a
# cruise speed) then ease OUT (decelerate to a hold) at hover_y, hold for
# `loiter_time` with a gentle bob/sway so it reads as ALIVE (not frozen), then
# accelerate away downward. Three placement variants (low/mid/high) ride the same
# pattern via hover_y — see EnemyRoster make_movement loiter_{low,mid,high}.
#
# Pattern pass 2026-06-05 (Roman): added hold-jiggle ("like bombers"), a true
# ease-IN to match the existing ease-OUT, and the low/mid/high hold band.

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
var _prev_jx: float = 0.0     # last frame's jiggle offset (compute_step is delta-based)
var _prev_jy: float = 0.0


func on_start(enemy) -> void:
	_phase = Phase.ENTERING
	_timer = 0.0
	_exit_speed = 0.0
	# Ease IN: start at a fraction of cruise and accelerate up (not a hard pop-in).
	_enter_vel = enter_speed * 0.3
	_hold_t = 0.0
	_prev_jx = 0.0
	_prev_jy = 0.0
	# Clamp hover_y so the enemy never settles in the bottom half (y > 135).
	hover_y = minf(hover_y, 135.0)
	phase_entered.emit("enter")


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTERING:
			var dist: float = hover_y - enemy.position.y
			if dist <= 0.0:
				# Arrived or overshot — snap to hover_y and hold.
				var snap: float = hover_y - enemy.position.y
				_enter_hold()
				return Vector2(0, snap)
			# Far → accelerate toward cruise; near → decelerate for the approach.
			var target_vel: float = enter_speed * clampf(dist / decel_dist, 0.0, 1.0)
			var rate: float = enter_accel if target_vel > _enter_vel else enter_decel
			_enter_vel = move_toward(_enter_vel, target_vel, rate * delta)
			_enter_vel = maxf(_enter_vel, 0.0)
			var step: float = _enter_vel * delta
			if enemy.position.y + step >= hover_y:
				step = hover_y - enemy.position.y
				_enter_hold()
			return Vector2(0, step)
		Phase.LOITERING:
			_timer += delta
			_hold_t += delta
			if _timer >= loiter_time:
				_phase = Phase.EXITING
				_exit_speed = enter_speed
				phase_entered.emit("exit")
				# Hand the residual jiggle offset back to 0 on the way out so the
				# exit starts clean (offsets are tiny but keep it tidy).
				return Vector2(-_prev_jx, -_prev_jy)
			# Sinusoidal bob (vertical) + slower sway (horizontal). compute_step is
			# delta-based, so return the CHANGE in offset since last frame.
			var jy: float = jiggle_amp_y * sin(_hold_t * jiggle_freq_y * TAU)
			var jx: float = jiggle_amp_x * sin(_hold_t * jiggle_freq_x * TAU)
			var d := Vector2(jx - _prev_jx, jy - _prev_jy)
			_prev_jx = jx
			_prev_jy = jy
			return d
		Phase.EXITING:
			_exit_speed = min(_exit_speed + exit_accel * delta, exit_max_speed)
			return Vector2(0, _exit_speed * delta)
	return Vector2.ZERO


func _enter_hold() -> void:
	_phase = Phase.LOITERING
	_timer = 0.0
	_hold_t = 0.0
	_enter_vel = 0.0
	_prev_jx = 0.0
	_prev_jy = 0.0
	phase_entered.emit("hold")
