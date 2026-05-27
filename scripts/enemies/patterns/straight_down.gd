extends "res://scripts/enemies/movement_pattern.gd"

# Constant vertical descent + optional sideways drift.
# 320×400 res rework: halved.
@export var speed: float = 100.0
@export var drift_x: float = 0.0


func on_start(_enemy) -> void:
	pass


func compute_step(_enemy, delta: float) -> Vector2:
	return Vector2(drift_x, speed) * delta
