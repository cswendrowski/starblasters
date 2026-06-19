extends "res://scripts/enemies/movement_pattern.gd"

# Cutter pattern: enters at travel_y from one side, crosses ~30% of the
# screen, then cuts diagonally to the opposite-bottom corner. `direction`
# = +1 (start left) or -1 (start right). Offscreen cleanup is handled by
# EnemyBase via FREE_OPPOSITE_SIDE on the host.

# 320×400 res rework: halved.
@export var travel_y: float = 72.0
@export var enter_speed: float = 120.0
@export var cut_speed: float = 168.0
@export var direction: int = 1
# Locomotion refactor 2026-06-19: speed is chassis-owned. The entry runs at the enemy's base
# move_speed; the diagonal cut is faster by this ratio (preserves the old 120→168 feel). The
# *_speed exports above are vestigial; travel_y (entry depth) is resolved by the director.
const CUT_RATIO: float = 168.0 / 120.0

enum Phase { ENTER, CUT }
var _phase: int = Phase.ENTER
var _t: float = 0.0


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	_phase = Phase.ENTER
	_t = 0.0
	# Authoritative spawn (Roman, 2026-05-17: cutter movement was
	# inconsistent). The old pattern relied on WaveDirector's formation +
	# a per-frame y-snap, which meant the cutter could spawn anywhere
	# horizontally and either (a) walk *toward* the trigger column or
	# (b) trip it on frame 1, depending on where formation dropped it.
	# Take ownership of the spawn point: enter at travel_y from the far
	# side of the screen so the entry is identical every time.
	# Spawn just outside the playfield band (not the full viewport) so the
	# cutter enters the gameplay area immediately and the trigger column is
	# inside the shootable zone.
	enemy.position.y = travel_y
	if direction > 0:
		enemy.position.x = Playfield.X_MIN - 12.0
	else:
		enemy.position.x = Playfield.X_MAX + 12.0


func compute_step(enemy, delta: float) -> Vector2:
	var spd: float = _move_speed(enemy)   # chassis base (locomotion refactor); the cut is faster
	match _phase:
		Phase.ENTER:
			# Pure horizontal walk in along travel_y. y was snapped once in
			# on_start; we don't keep re-snapping each frame (the previous
			# version's dy = travel_y - position.y reset y EVERY frame,
			# which teleported the cutter back to travel_y after any
			# external nudge).
			var dx: float = spd * float(direction) * delta
			var trigger_x: float = Playfield.X_MIN + Playfield.W * 0.30 if direction > 0 else Playfield.X_MIN + Playfield.W * 0.70
			var new_x: float = enemy.position.x + dx
			if (direction > 0 and new_x >= trigger_x) or (direction < 0 and new_x <= trigger_x):
				_phase = Phase.CUT
			return Vector2(dx, 0)
		Phase.CUT:
			var v: Vector2 = Vector2(float(-direction) * 0.7, 1.0).normalized() * spd * CUT_RATIO
			return v * delta
	return Vector2.ZERO
