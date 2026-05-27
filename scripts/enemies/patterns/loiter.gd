extends "res://scripts/enemies/movement_pattern.gd"

# Enter from top, snap-hold at hover_y for `loiter_time` seconds, then
# accelerate away downward.

# 320×400 res rework: y/speed halved.
@export var hover_y: float = 88.0
@export var enter_speed: float = 88.0
@export var loiter_time: float = 3.0
@export var exit_accel: float = 300.0
@export var exit_max_speed: float = 280.0

signal phase_entered(phase_name: String)

enum Phase { ENTERING, LOITERING, EXITING }
var _phase: int = Phase.ENTERING
var _timer: float = 0.0
var _exit_speed: float = 0.0


func on_start(_enemy) -> void:
	_phase = Phase.ENTERING
	_timer = 0.0
	_exit_speed = 0.0
	phase_entered.emit("enter")


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTERING:
			var step_y: float = enter_speed * delta
			# Snap exactly to hover_y when we'd overshoot — no overshoot
			# means the LOITER phase always starts from the same height
			# regardless of frame rate.
			if enemy.position.y + step_y >= hover_y:
				step_y = hover_y - enemy.position.y
				_phase = Phase.LOITERING
				_timer = 0.0
				phase_entered.emit("hold")
			return Vector2(0, step_y)
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
