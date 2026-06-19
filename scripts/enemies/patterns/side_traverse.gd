extends "res://scripts/enemies/movement_pattern.gd"

# Crosses the screen horizontally at a fixed y. Used by the Minelayer which
# drops bomblets in a line as it passes through. `direction` is +1 (L→R)
# or -1 (R→L). Offscreen cleanup is handled by EnemyBase via the host's
# `offscreen_mode = FREE_OPPOSITE_SIDE`.

# 320×400 res rework: halved.
@export var travel_y: float = 80.0
@export var speed: float = 60.0
@export var direction: int = 1


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	# Authoritative spawn (Roman 2026-06-05 pattern pass): a Crosser OWNS its entry —
	# start just off the playfield band on the spawn side and traverse in then out,
	# instead of keeping whatever x it was placed at (which left it starting mid-screen
	# in isolation / the visualizer). Mirrors side_cut. y snapped once here (contract
	# allows initial placement in on_start). Row height-stagger (so crossers don't run
	# over each other) is P2.
	enemy.position.y = travel_y
	if direction > 0:
		enemy.position.x = Playfield.X_MIN - 12.0
	else:
		enemy.position.x = Playfield.X_MAX + 12.0


func compute_step(enemy, delta: float) -> Vector2:
	# Cross speed is chassis-owned now (locomotion refactor); `speed` is vestigial. travel_y (the
	# cross depth) is resolved from the enemy/formation depth by the director before spawn.
	return Vector2(_move_speed(enemy) * float(direction) * delta, 0)
