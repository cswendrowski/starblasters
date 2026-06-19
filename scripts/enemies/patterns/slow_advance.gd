extends "res://scripts/enemies/movement_pattern.gd"

# Anchor (m6 §13): a slow, steady straight descent for big hulls. Descends at
# enter_speed to hold_y, then station-keeps.
#
# Pattern pass 2026-06-05 (Roman): the old sine x-drift ("it's side-to-side
# loiter, not an advance") is removed — an Anchor reads as a slow Diver, not a
# weaver. For a pure continuous descent with no station-keep (the chaff "slow
# Diver" use), set hold_y past the bottom of the band; for a stationary patrol
# (a big hull holding a line) set hold_y on-screen.

# 320×400 res rework: halved.
@export var hold_y: float = 88.0
@export var enter_speed: float = 60.0

var _holding: bool = false


func on_start(_enemy) -> void:
	_holding = false


func compute_step(enemy, delta: float) -> Vector2:
	if _holding:
		return Vector2.ZERO
	# Descent speed is chassis-owned now (locomotion refactor); `enter_speed` is vestigial.
	var step_y: float = _move_speed(enemy) * delta
	if enemy.position.y + step_y >= hold_y:
		step_y = hold_y - enemy.position.y
		_holding = true
	return Vector2(0, step_y)
