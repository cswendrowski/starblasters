extends "res://scripts/enemies/movement_pattern.gd"

# Interceptor (Roman 2026-06-08 rework): enters HORIZONTALLY across the top, then turns
# and DIVES straight down into a lane. A two-phase "strafe-in then plunge" — a switch-up
# from the typical vertical entry / horizontal cross. (Was a straight dive with a sin-x
# rightward drift, which read as a strange wobble.)
#
# Host disables the parallax recycle so it leaves for good after one pass.

const Playfield = preload("res://scripts/systems/playfield.gd")

@export var dive_speed: float = 220.0       # straight-down plunge (phase 2)
@export var enter_speed: float = 180.0      # horizontal sweep speed (phase 1)
@export var enter_descend: float = 35.0     # gentle descent during the sweep so it enters frame
@export var sweep_time: float = 0.6         # seconds of horizontal entry before the dive
# Locomotion refactor 2026-06-19: speed is chassis-owned. The sweep runs at the enemy's base
# move_speed; the plunge + entry-descent are fractions of it (ratios preserve the old 180/220/35
# feel). The *_speed / enter_descend exports above are vestigial.
const DIVE_RATIO: float = 220.0 / 180.0
const ENTER_DESCEND_RATIO: float = 35.0 / 180.0

var _t: float = 0.0
var _dir: float = 1.0   # +1 sweep right, -1 sweep left


func on_start(enemy) -> void:
	_t = 0.0
	enemy.allow_side_exit = true
	# Sweep toward the roomier side so the horizontal entry reads as a cross before the
	# dive (spawned left of centre -> sweep right, and vice versa).
	_dir = 1.0 if enemy.position.x < Playfield.CENTER.x else -1.0


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var spd: float = _move_speed(enemy)
	if _t < sweep_time:
		# Phase 1: horizontal entry with a shallow descent. Clamp the X step so the
		# sweep never carries the diver out of the playfield band.
		var nx: float = clampf(
			enemy.position.x + _dir * spd * delta,
			Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
		return Vector2(nx - enemy.position.x, spd * ENTER_DESCEND_RATIO * delta)
	# Phase 2: turn and plunge straight down (faster than the sweep) into the lane it's now over.
	return Vector2(0.0, spd * DIVE_RATIO * delta)
