extends "res://scripts/enemies/patterns/jet.gd"

# Charger Jet variant (Roman, 2026-05-17 Movement Lab v2). Replaces the
# original strafe-jet. State machine:
#   CRUISE — long straight pass at cruise_speed; minimal turning.
#   TURN   — slow to slow_speed and pivot toward the player.
#   CHARGE — once aimed, accelerate hard toward the player and barrel
#            through, then transition back to CRUISE for the next pass.

enum Phase { CRUISE, TURN, CHARGE }

@export var cruise_speed: float = 110.0
@export var slow_speed: float = 30.0
@export var charge_speed: float = 260.0
@export var cruise_duration: float = 1.8       # seconds before forcing a turn
@export var aim_tolerance_deg: float = 8.0     # how close to on-target before charge

var _phase: int = Phase.CRUISE
var _phase_t: float = 0.0


func on_start(enemy) -> void:
	super.on_start(enemy)
	_phase = Phase.CRUISE
	_phase_t = 0.0
	target_speed = cruise_speed
	turn_speed_falloff = 0.05
	weave_amplitude_deg = 1.5


func compute_step(enemy, delta: float) -> Vector2:
	_phase_t += delta
	var player := _find_player(enemy)
	match _phase:
		Phase.CRUISE:
			target_speed = cruise_speed
			turn_rate_at_min = 60.0
			if _should_end_cruise(enemy, player):
				_phase = Phase.TURN
				_phase_t = 0.0
		Phase.TURN:
			target_speed = slow_speed
			turn_rate_at_min = 220.0
			if _is_aimed_at(enemy, player, aim_tolerance_deg):
				_phase = Phase.CHARGE
				_phase_t = 0.0
		Phase.CHARGE:
			target_speed = charge_speed
			turn_rate_at_min = 90.0
			if _phase_t > 1.4 or _passed_target(enemy, player):
				_phase = Phase.CRUISE
				_phase_t = 0.0
	return super.compute_step(enemy, delta)


func _should_end_cruise(enemy, player) -> bool:
	if _phase_t > cruise_duration:
		return true
	var vp: Vector2 = enemy.get_viewport_rect().size
	const NEAR: float = 30.0
	if enemy.position.x < NEAR or enemy.position.x > vp.x - NEAR \
		or enemy.position.y < NEAR or enemy.position.y > vp.y - NEAR:
		return true
	return false


func _is_aimed_at(enemy, player, tol_deg: float) -> bool:
	if player == null:
		return false
	var rot: float = enemy.rotation - PI * 0.5
	var fwd: Vector2 = Vector2(cos(rot), sin(rot))
	var to_p: Vector2 = player.global_position - enemy.global_position
	if to_p.length_squared() < 1.0:
		return false
	return fwd.dot(to_p.normalized()) > cos(deg_to_rad(tol_deg))


func _passed_target(enemy, player) -> bool:
	if player == null:
		return false
	var rot: float = enemy.rotation - PI * 0.5
	var fwd: Vector2 = Vector2(cos(rot), sin(rot))
	var to_p: Vector2 = player.global_position - enemy.global_position
	return fwd.dot(to_p) < 0.0
