extends "res://scripts/enemies/patterns/jet.gd"

# Vector Jet variant. Roman, 2026-05-17 Movement Lab feedback: "vector
# jets that can aggressively j-turn, burning off speed to come around."
# Inherits jet.gd; bumps the turn rate at low speed AND auto-decelerates
# when the target is behind the nose, so the jet brakes into the turn.

@export var slow_speed: float = 40.0
@export var brake_rate: float = 90.0
# Locomotion refactor 2026-06-19: phase speed/turn/accel are chassis-relative (max_speed is the
# seeded chassis move_speed; _turn_rate/_accel are the chassis stats). Ratios reproduce the old
# 40/220/35 feel. The slow_speed export above is vestigial.
const SLOW_RATIO: float = 40.0 / 180.0
const TURN_RATIO_V: float = 220.0 / 300.0
const ACCEL_RATIO_V: float = 35.0 / 600.0


func on_start(enemy) -> void:
	super.on_start(enemy)
	# Lower turn-at-min + softer accel so the vector jet fishtails through
	# its turns instead of snapping (Roman, 2026-05-17 Movement Lab v2:
	# "Vector needs some more inertia so that it fishtails and drifts a
	# bit more"). Wider falloff so the high-speed pass is still floaty.
	turn_rate_at_min = _turn_rate(enemy) * TURN_RATIO_V
	turn_speed_falloff = 0.35
	weave_amplitude_deg = 5.0
	# Slow the speed-adjust ramp so deceleration takes a beat — the body
	# keeps carrying through the turn before the nose realigns.
	accel = _accel(enemy) * ACCEL_RATIO_V


func compute_step(enemy, delta: float) -> Vector2:
	var player := _find_player(enemy)
	if player and enemy is Node2D:
		var rot: float = enemy.rotation - PI * 0.5
		var fwd: Vector2 = Vector2(cos(rot), sin(rot))
		var to_p: Vector2 = (player.global_position - enemy.global_position)
		if to_p.length_squared() > 1.0:
			var dir: Vector2 = to_p.normalized()
			# When the target is well off the nose (dot < ~0.5), brake into
			# the turn — accelerate toward slow_speed instead of cruising.
			var alignment: float = fwd.dot(dir)
			if alignment < 0.5:
				target_speed = max_speed * SLOW_RATIO
			else:
				# Realigned; resume cruise.
				target_speed = max_speed * 0.85
	return super.compute_step(enemy, delta)
