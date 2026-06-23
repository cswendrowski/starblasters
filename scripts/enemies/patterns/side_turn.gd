extends "res://scripts/enemies/movement_pattern.gd"

# Side Turn (Roman 2026-06-08): advance HORIZONTALLY in from the spawn side, then a rounded turn
# DOWN into the lane it reaches, then descend to exit the bottom. A switch-up from the straight
# horizontal cross.
#
# `side_dive` collapsed into this 2026-06-22: it was just a SideTurn with a shorter advance, and
# since the descent speed is chassis-owned (enemy.move_speed) there was no real second pattern —
# one SideTurn covers both. `side_dive` is now an alias for `side_turn` (enemy_roster
# MOVEMENT_ALIASES + the eligibility editor's KEY_REMAP).

const Playfield = preload("res://scripts/systems/playfield.gd")

@export var advance_time: float = 0.6      # seconds advancing before the turn
@export var turn_time: float = 0.45        # seconds the rounded turn takes
# Locomotion refactor 2026-06-19: the post-turn descent is the chassis move_speed; the horizontal
# advance is a fraction of it. The *_speed exports above are vestigial; advance_time/turn_time stay
# pattern shape.
const ENTER_RATIO: float = 160.0 / 180.0

var _t: float = 0.0
var _phase: int = 0    # 0 advance, 1 turn, 2 descend
var _dir: float = 1.0
var _target_x: float = 0.0      # lane center the turn delivers the enemy into
var _turn_from_x: float = 0.0   # x when the turn began (ease origin)


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	_t = 0.0
	_phase = 0
	_target_x = 0.0
	_turn_from_x = 0.0
	# Advance toward the roomier side so it reads as coming IN from an edge.
	_dir = 1.0 if enemy.position.x < Playfield.CENTER.x else -1.0


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var ms: float = _move_speed(enemy)         # chassis descent speed (locomotion refactor)
	var enter_v: float = ms * ENTER_RATIO      # horizontal advance, a fraction of it
	match _phase:
		0:  # horizontal advance
			var nx: float = clampf(enemy.position.x + _dir * enter_v * delta,
				Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
			if _t >= advance_time:
				_phase = 1
				_t = 0.0
				# Snap onto the nearest LANE CENTER to where the advance ended so the turn delivers
				# the enemy cleanly INTO a lane instead of descending at an arbitrary x (Roman
				# 2026-06-22: "make sure they go into their lane" — the old free cos-blend left the
				# descent misaligned with the lane grid).
				_turn_from_x = nx
				_target_x = Lanes.lane_center(Lanes.nearest_lane(nx))
			return Vector2(nx - enemy.position.x, 0.0)
		1:  # rounded quarter-turn: ease X to the lane center while the descent ramps in
			var u: float = clampf(_t / maxf(turn_time, 0.0001), 0.0, 1.0)
			var eased: float = smoothstep(0.0, 1.0, u)
			var ang: float = lerpf(0.0, PI * 0.5, eased)  # 0=horizontal..PI/2=down
			var tx: float = lerpf(_turn_from_x, _target_x, eased)
			if u >= 1.0:
				_phase = 2
			return Vector2(tx - enemy.position.x, sin(ang) * ms * delta)
		_:  # descend straight down the lane it arrived in (locked so it can't drift off-center)
			return Vector2(_target_x - enemy.position.x, ms * delta)
