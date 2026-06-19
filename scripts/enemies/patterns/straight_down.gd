extends "res://scripts/enemies/movement_pattern.gd"

# Constant vertical descent + optional sideways drift.
# 320×400 res rework: halved.
@export var speed: float = 120.0
@export var drift_x: float = 0.0


func on_start(_enemy) -> void:
	pass


func compute_step(enemy, delta: float) -> Vector2:
	# Speed is chassis-owned now (locomotion refactor 2026-06-19): read it off the enemy. The
	# `speed` export is vestigial (set by the old make_movement helpers) and ignored.
	return Vector2(drift_x, _move_speed(enemy)) * delta


func path_phase_capable() -> bool:
	return true  # pure descent — band-Y is monotonic
