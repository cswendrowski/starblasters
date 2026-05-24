extends "res://scripts/enemies/movement_pattern.gd"

# Cutter movement (Roman, 2026-05-24): enter from a side at travel_y,
# cross horizontally, then PONG back. Repeat for a random 1d6 cycles.
# After the final cycle the enemy keeps going past the playfield edge
# and offscreen-cleanup frees it. Firing is handled by the host's
# shoot_pattern + ShootTimer — the pattern only owns movement.
#
# `direction` is the initial heading: +1 (entering from the left,
# moving right) or -1 (entering from the right, moving left). Set by
# Roster.make_movement per spawn so the wave can alternate sides.

@export var speed: float = 250.0
@export var travel_y: float = 80.0
@export var cycles_min: int = 1
@export var cycles_max: int = 6
@export var direction: int = 1

# A "cycle" is one full traversal of the playfield band (one side to
# the opposite side). _cycles_done increments each time the cutter
# crosses the far bound. When _cycles_done == _cycles_target the
# pattern stops flipping and lets the cutter exit on the side it's
# currently heading toward.
var _cycles_done: int = 0
var _cycles_target: int = 1
var _direction_runtime: int = 1
var _exiting: bool = false

# Margin past the playfield edge at which we register a "pong". Matches
# enemy_core's SIDE_MARGIN intent (sprite ~16 px wide, want it fully off
# the playfield before reversing so the reversal happens visibly past
# the edge rather than inside the playfield).
const BOUND_OUTER: float = 8.0


func on_start(enemy) -> void:
	# Side-exit must be ON throughout — both during the cycles (so we
	# pass the playfield edge before flipping) AND on the final exit
	# (so we leave cleanly). enemy_core's _clamp_to_sides would otherwise
	# clamp us before we ever crossed the edge.
	enemy.allow_side_exit = true
	_cycles_done = 0
	_cycles_target = randi_range(max(1, cycles_min), max(cycles_min, cycles_max))
	_direction_runtime = 1 if direction >= 0 else -1
	_exiting = false
	# Authoritative spawn: place just outside the playfield band on the
	# entering side, at travel_y. Matches side_cut/side_traverse pattern.
	enemy.position.y = travel_y
	if _direction_runtime > 0:
		enemy.position.x = Playfield.X_MIN - 12.0
	else:
		enemy.position.x = Playfield.X_MAX + 12.0


func compute_step(enemy, delta: float) -> Vector2:
	var step: Vector2 = Vector2(speed * float(_direction_runtime) * delta, 0.0)
	if _exiting:
		return step
	# Detect crossing the far bound. Use the bound the cutter is currently
	# heading toward.
	var x_after: float = enemy.position.x + step.x
	if _direction_runtime > 0 and x_after >= Playfield.X_MAX + BOUND_OUTER:
		_cycles_done += 1
		if _cycles_done >= _cycles_target:
			_exiting = true  # let it sail off
		else:
			_direction_runtime = -1
	elif _direction_runtime < 0 and x_after <= Playfield.X_MIN - BOUND_OUTER:
		_cycles_done += 1
		if _cycles_done >= _cycles_target:
			_exiting = true
		else:
			_direction_runtime = 1
	return step
