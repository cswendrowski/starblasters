extends "res://scripts/enemies/movement_pattern.gd"

# Interceptor: dives top→bottom at high speed with a gentle sinusoidal x
# drift. Host disables the parallax recycle so it leaves the screen for
# good after one pass.

# 320×400 res rework: halved.
@export var speed: float = 240.0
@export var drift_x: float = 30.0

var _t: float = 0.0


func on_start(enemy) -> void:
	_t = 0.0
	enemy.allow_side_exit = true


func compute_step(_enemy, delta: float) -> Vector2:
	_t += delta
	return Vector2(sin(_t * 1.3) * drift_x * delta, speed * delta)
