extends "res://scripts/enemies/movement_pattern.gd"

# Frigate: slow descent to hold_y, then station-keep with a gentle sine
# drift in x so the player has to lead it.

# 320×400 res rework: halved.
@export var hold_y: float = 88.0
@export var enter_speed: float = 35.0
@export var drift_x_amp: float = 32.0
@export var drift_x_speed: float = 0.6

var _t: float = 0.0
var _base_x: float = 0.0
var _holding: bool = false


func on_start(enemy) -> void:
	_t = 0.0
	_base_x = enemy.position.x
	_holding = false


func compute_step(enemy, delta: float) -> Vector2:
	var step_y: float = 0.0
	if not _holding:
		step_y = enter_speed * delta
		if enemy.position.y + step_y >= hold_y:
			step_y = hold_y - enemy.position.y
			_holding = true
	_t += delta
	# Drift inside the 216-px playfield band, not the full viewport.
	var max_amp: float = min(_base_x - (Playfield.X_MIN + 22.0), (Playfield.X_MAX - 22.0) - _base_x)
	var safe: float = min(drift_x_amp, max(max_amp, 6.0))
	var target_x: float = _base_x + sin(_t * drift_x_speed) * safe
	return Vector2(target_x - enemy.position.x, step_y)
