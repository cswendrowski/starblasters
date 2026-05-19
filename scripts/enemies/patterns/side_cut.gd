extends "res://scripts/enemies/movement_pattern.gd"

# Cutter pattern: enters at travel_y from one side, crosses ~30% of the
# screen, then cuts diagonally to the opposite-bottom corner. `direction`
# = +1 (start left) or -1 (start right). Offscreen cleanup is handled by
# EnemyBase via FREE_OPPOSITE_SIDE on the host.

# 320×400 res rework: halved.
@export var travel_y: float = 72.0
@export var enter_speed: float = 130.0
@export var cut_speed: float = 210.0
@export var direction: int = 1

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
	var w: float = enemy.get_viewport_rect().size.x
	enemy.position.y = travel_y
	if direction > 0:
		enemy.position.x = -12.0          # offscreen left, walks right
	else:
		enemy.position.x = w + 12.0       # offscreen right, walks left


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTER:
			# Pure horizontal walk in along travel_y. y was snapped once in
			# on_start; we don't keep re-snapping each frame (the previous
			# version's dy = travel_y - position.y reset y EVERY frame,
			# which teleported the cutter back to travel_y after any
			# external nudge).
			var dx: float = enter_speed * float(direction) * delta
			var w: float = enemy.get_viewport_rect().size.x
			var trigger_x: float = w * 0.30 if direction > 0 else w * 0.70
			var new_x: float = enemy.position.x + dx
			if (direction > 0 and new_x >= trigger_x) or (direction < 0 and new_x <= trigger_x):
				_phase = Phase.CUT
			return Vector2(dx, 0)
		Phase.CUT:
			var v: Vector2 = Vector2(float(-direction) * 0.7, 1.0).normalized() * cut_speed
			return v * delta
	return Vector2.ZERO
