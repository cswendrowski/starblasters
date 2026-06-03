extends "res://scripts/enemies/movement_pattern.gd"

# Enter from top, decelerate smoothly to a hold at hover_y (clamped to the
# top half of the 270-px viewport) for `loiter_time` seconds, then
# accelerate away downward.

# 320×400 res rework: y/speed halved.
@export var hover_y: float = 88.0
@export var enter_speed: float = 60.0
@export var loiter_time: float = 3.0
@export var exit_accel: float = 300.0
@export var exit_max_speed: float = 280.0

# Smooth entry: how quickly the ship decelerates as it nears hover_y.
# Larger = heavier feel. 220 px/s² gives a "heavy" approach arc.
@export var enter_decel: float = 220.0

signal phase_entered(phase_name: String)

enum Phase { ENTERING, LOITERING, EXITING }
var _phase: int = Phase.ENTERING
var _timer: float = 0.0
var _exit_speed: float = 0.0
var _enter_vel: float = 0.0  # current downward velocity during ENTERING


func on_start(enemy) -> void:
	_phase = Phase.ENTERING
	_timer = 0.0
	_exit_speed = 0.0
	_enter_vel = enter_speed
	# Clamp hover_y so the enemy never settles in the bottom half (y > 135).
	hover_y = minf(hover_y, 135.0)
	phase_entered.emit("enter")


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTERING:
			# Decelerate as we approach hover_y — heavy, weighted feel.
			var dist: float = hover_y - enemy.position.y
			if dist <= 0.0:
				# Arrived or overshot — snap to hover_y and hold.
				var snap: float = hover_y - enemy.position.y
				_phase = Phase.LOITERING
				_timer = 0.0
				_enter_vel = 0.0
				phase_entered.emit("hold")
				return Vector2(0, snap)
			# Decelerate when close, accelerate otherwise — smooth arc.
			var target_vel: float = enter_speed * clampf(dist / 40.0, 0.0, 1.0)
			_enter_vel = move_toward(_enter_vel, target_vel, enter_decel * delta)
			_enter_vel = maxf(_enter_vel, 0.0)
			var step: float = _enter_vel * delta
			if enemy.position.y + step >= hover_y:
				step = hover_y - enemy.position.y
				_phase = Phase.LOITERING
				_timer = 0.0
				_enter_vel = 0.0
				phase_entered.emit("hold")
			return Vector2(0, step)
		Phase.LOITERING:
			_timer += delta
			if _timer >= loiter_time:
				_phase = Phase.EXITING
				_exit_speed = enter_speed
				phase_entered.emit("exit")
			return Vector2.ZERO
		Phase.EXITING:
			_exit_speed = min(_exit_speed + exit_accel * delta, exit_max_speed)
			return Vector2(0, _exit_speed * delta)
	return Vector2.ZERO
