extends "res://scripts/enemies/movement_pattern.gd"

# Bulwark: slow drift down to hold_y, then very slow lateral wander.
# Bulwark itself has no weapons; the shield-projection logic lives on
# bulwark.gd which keeps nearby allies shielded.

# 320×400 res rework: halved.
@export var hold_y: float = 80.0
@export var enter_speed: float = 25.0
@export var drift_amp: float = 36.0
@export var drift_speed: float = 0.35

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
	var max_amp: float = min(_base_x - (Playfield.X_MIN + 28.0), (Playfield.X_MAX - 28.0) - _base_x)
	var safe: float = min(drift_amp, max(max_amp, 6.0))
	var target_x: float = _base_x + sin(_t * drift_speed) * safe
	return Vector2(target_x - enemy.position.x, step_y)
