extends "res://scripts/enemies/movement_pattern.gd"

# Side Turn (Roman 2026-06-08): advance HORIZONTALLY in from the spawn side, then a rounded turn
# DOWN into the lane it reaches, then descend to exit the bottom. `side_dive` is the same with a
# swift descent (high down_speed). A switch-up from the straight horizontal cross.

const Playfield = preload("res://scripts/systems/playfield.gd")

@export var enter_speed: float = 160.0     # horizontal advance speed
@export var down_speed: float = 180.0      # post-turn descent (side_dive bumps this up)
@export var advance_time: float = 0.6      # seconds advancing before the turn
@export var turn_time: float = 0.45        # seconds the rounded turn takes

var _t: float = 0.0
var _phase: int = 0    # 0 advance, 1 turn, 2 descend
var _dir: float = 1.0


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	_t = 0.0
	_phase = 0
	# Advance toward the roomier side so it reads as coming IN from an edge.
	_dir = 1.0 if enemy.position.x < Playfield.CENTER.x else -1.0


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	match _phase:
		0:  # horizontal advance
			var nx: float = clampf(enemy.position.x + _dir * enter_speed * delta,
				Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
			if _t >= advance_time:
				_phase = 1
				_t = 0.0
			return Vector2(nx - enemy.position.x, 0.0)
		1:  # rounded quarter-turn: blend the velocity from horizontal to straight-down
			var u: float = clampf(_t / maxf(turn_time, 0.0001), 0.0, 1.0)
			var ang: float = lerpf(0.0, PI * 0.5, u * u * (3.0 - 2.0 * u))  # 0=horizontal..PI/2=down
			var spd: float = lerpf(enter_speed, down_speed, u)
			if u >= 1.0:
				_phase = 2
			return Vector2(_dir * cos(ang) * spd * delta, sin(ang) * spd * delta)
		_:  # descend
			return Vector2(0.0, down_speed * delta)
