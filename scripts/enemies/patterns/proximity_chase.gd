extends "res://scripts/enemies/movement_pattern.gd"

# Proximity Chase (Roman 2026-06-08, ported from smart mine / smart bomblet): drift straight down
# (a plain medium descent) until the player comes within `proximity`, then a brief telegraph and a
# relentless accel-toward-player chase with band-edge bounce. Activation is by PROXIMITY, not by
# placement — until armed it's just a straight descender ("straight_medium otherwise").
#
# Emits phase_entered("transition") and ("armed") so the host can swap its sprite frames / sfx
# (smart mine: dormant F0 → transition F1 → armed F2). Movement-only; the contact/explode payload
# stays on the host.

const Playfield = preload("res://scripts/playfield.gd")

signal phase_entered(phase_name: String)

@export var drift_speed: float = 180.0     # dormant descent (straight_medium rung)
@export var proximity: float = 80.0        # activation radius
@export var transition_time: float = 0.18  # telegraph before the chase engages
@export var chase_accel: float = 360.0
@export var chase_max_speed: float = 180.0
@export var bounce_damp: float = 0.5       # side-wall bounce velocity retention

enum Ph { DRIFT, TRANSITION, CHASE }
var _ph: int = Ph.DRIFT
var _t: float = 0.0
var _vel: Vector2 = Vector2.ZERO


func on_start(_enemy) -> void:
	_ph = Ph.DRIFT
	_t = 0.0
	_vel = Vector2(0.0, drift_speed)


func compute_step(enemy, delta: float) -> Vector2:
	match _ph:
		Ph.DRIFT:
			var p = enemy.find_player() if enemy.has_method("find_player") else null
			if p != null and is_instance_valid(p) \
					and enemy.global_position.distance_to(p.global_position) <= proximity:
				_ph = Ph.TRANSITION
				_t = 0.0
				_vel = Vector2.ZERO
				phase_entered.emit("transition")
				return Vector2.ZERO
			return _vel * delta
		Ph.TRANSITION:
			_t += delta
			if _t >= transition_time:
				_ph = Ph.CHASE
				phase_entered.emit("armed")
			return Vector2.ZERO
		_:  # CHASE — relentless accel toward the player, bounce off the side walls
			var p2 = enemy.find_player() if enemy.has_method("find_player") else null
			if p2 != null and is_instance_valid(p2):
				var dir: Vector2 = (p2.global_position - enemy.global_position)
				if dir.length_squared() > 0.01:
					_vel = _vel.move_toward(dir.normalized() * chase_max_speed, chase_accel * delta)
			var x: float = enemy.position.x
			if x <= Playfield.X_MIN + 4.0 and _vel.x < 0.0:
				_vel.x = -_vel.x * bounce_damp
			elif x >= Playfield.X_MAX - 4.0 and _vel.x > 0.0:
				_vel.x = -_vel.x * bounce_damp
			return _vel * delta
