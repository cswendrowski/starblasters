extends "res://scripts/enemies/movement_pattern.gd"

# Skirmisher: dive to advance_y, hold/fire briefly, hard-reverse back to
# the top, repeat N times, then break off horizontally and leave.

# 320×400 res rework: halved.
@export var advance_y: float = 192.0
@export var hold_time: float = 0.6
@export var advance_speed: float = 180.0
@export var retreat_speed: float = 260.0
@export var break_speed: float = 240.0
@export var cycles: int = 2

enum Phase { ADVANCE, HOLD, RETREAT, BREAK }
var _phase: int = Phase.ADVANCE
var _t: float = 0.0
var _cycle: int = 0
var _break_dir: float = 0.0


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	_phase = Phase.ADVANCE
	_t = 0.0
	_cycle = 0
	_break_dir = 0.0


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ADVANCE:
			var step_y: float = advance_speed * delta
			if enemy.position.y + step_y >= advance_y:
				step_y = advance_y - enemy.position.y
				_phase = Phase.HOLD
				_t = 0.0
			return Vector2(0, step_y)
		Phase.HOLD:
			_t += delta
			if _t >= hold_time:
				_phase = Phase.RETREAT
			return Vector2.ZERO
		Phase.RETREAT:
			var step_y2: float = -retreat_speed * delta
			if enemy.position.y + step_y2 <= 24.0:
				step_y2 = 24.0 - enemy.position.y
				_cycle += 1
				if _cycle >= cycles:
					var w: float = enemy.get_viewport_rect().size.x
					_break_dir = -1.0 if enemy.position.x < w * 0.5 else 1.0
					_phase = Phase.BREAK
				else:
					_phase = Phase.ADVANCE
			return Vector2(0, step_y2)
		Phase.BREAK:
			return Vector2(_break_dir * break_speed * delta, 24.0 * delta)
	return Vector2.ZERO
