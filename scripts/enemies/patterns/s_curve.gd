extends "res://scripts/enemies/movement_pattern.gd"

# Sin-wave horizontal swing around the spawn x, while descending. Amplitude
# auto-clamps so a spawn near the wall doesn't push the enemy out the side.

# 320×400 res rework: halved.
@export var down_speed: float = 90.0
@export var amplitude: float = 70.0
@export var frequency: float = 1.4

var _t: float = 0.0
var _start_x: float = 0.0


func on_start(enemy) -> void:
	_t = 0.0
	_start_x = enemy.position.x


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var sw: float = enemy.get_viewport_rect().size.x
	var max_amp: float = min(_start_x - 22.0, sw - _start_x - 22.0)
	var safe_amp: float = min(amplitude, max(max_amp, 8.0))
	var target_x: float = _start_x + sin(_t * frequency) * safe_amp
	return Vector2(target_x - enemy.position.x, down_speed * delta)
