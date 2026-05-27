extends "res://scripts/enemies/movement_pattern.gd"

# Crosses the screen horizontally at a fixed y. Used by the Minelayer which
# drops bomblets in a line as it passes through. `direction` is +1 (L→R)
# or -1 (R→L). Offscreen cleanup is handled by EnemyBase via the host's
# `offscreen_mode = FREE_OPPOSITE_SIDE`.

# 320×400 res rework: halved.
@export var travel_y: float = 80.0
@export var speed: float = 44.0
@export var direction: int = 1


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	# Snap-place at travel_y once at spawn. Doing this in on_start is
	# allowed by the contract — patterns may set initial position here,
	# they just can't mutate position from compute_step.
	enemy.position.y = travel_y


func compute_step(_enemy, delta: float) -> Vector2:
	return Vector2(speed * float(direction) * delta, 0)
