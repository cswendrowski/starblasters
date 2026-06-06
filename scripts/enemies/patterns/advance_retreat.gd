extends "res://scripts/enemies/movement_pattern.gd"

# Skirmisher (m6 §13): dive to advance_y, hold/fire briefly, retreat toward the
# top, repeat N times, then EXIT by accelerating up and off the top of the screen.
#
# Pattern pass 2026-06-05 (Roman): endpoints are now EASED — the ship accelerates
# out of each turn and decelerates into the next, so the up/down reads as momentum
# instead of a mechanical hard-reverse. The exit was a sideways break; it is now
# "accelerate up & off" (a clean disengage upward).

# 320×400 res rework: halved.
@export var advance_y: float = 192.0
@export var hold_time: float = 0.6
@export var advance_speed: float = 144.0   # cruise speed (descending)
@export var retreat_speed: float = 208.0   # cruise speed (ascending)
@export var cycles: int = 2

# Endpoint easing: accelerate out of a turn at `accel`; decelerate over the last
# `decel_dist` px into an endpoint. `endpoint_min_speed` floors the eased target
# so the approach doesn't crawl asymptotically (Zeno) into the snap.
@export var accel: float = 500.0
@export var decel_dist: float = 28.0
@export var endpoint_min_speed: float = 50.0

# Exit: accelerate upward off the top.
@export var exit_accel: float = 600.0
@export var exit_max_speed: float = 480.0

signal phase_entered(phase_name: String)

enum Phase { ADVANCE, HOLD, RETREAT, EXIT }
var _phase: int = Phase.ADVANCE
var _t: float = 0.0
var _cycle: int = 0
var _vel: float = 0.0

const TOP_Y := 24.0


func on_start(enemy) -> void:
	# Exit is upward off the top — needs FREE_ANY_EDGE so it despawns there
	# (CYCLE_BOTTOM never frees on the top edge). Guarded so the visualizer's
	# bare dummy (no offscreen_mode property) doesn't choke.
	if "offscreen_mode" in enemy:
		enemy.offscreen_mode = 1  # EnemyBase.OffscreenMode.FREE_ANY_EDGE
	_phase = Phase.ADVANCE
	_t = 0.0
	_cycle = 0
	_vel = 0.0
	phase_entered.emit("advance")


# Eased speed toward an endpoint `dist` px away: cruise far out, ramp down inside
# decel_dist, floored at endpoint_min_speed so the snap actually lands.
func _eased(cruise: float, dist: float) -> float:
	var t: float = cruise * clampf(dist / decel_dist, 0.0, 1.0)
	return maxf(t, endpoint_min_speed)


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ADVANCE:
			var dist: float = advance_y - enemy.position.y
			_vel = move_toward(_vel, _eased(advance_speed, dist), accel * delta)
			var step: float = _vel * delta
			if enemy.position.y + step >= advance_y:
				step = advance_y - enemy.position.y
				_phase = Phase.HOLD
				_t = 0.0
				_vel = 0.0
				phase_entered.emit("hold")
			return Vector2(0, step)
		Phase.HOLD:
			_t += delta
			if _t >= hold_time:
				_phase = Phase.RETREAT
				_vel = 0.0
				phase_entered.emit("retreat")
			return Vector2.ZERO
		Phase.RETREAT:
			var dist2: float = enemy.position.y - TOP_Y
			_vel = move_toward(_vel, _eased(retreat_speed, dist2), accel * delta)
			var step2: float = -_vel * delta
			if enemy.position.y + step2 <= TOP_Y:
				step2 = TOP_Y - enemy.position.y
				_cycle += 1
				_vel = 0.0
				if _cycle >= cycles:
					_phase = Phase.EXIT
					phase_entered.emit("exit")
				else:
					_phase = Phase.ADVANCE
					phase_entered.emit("advance")
			return Vector2(0, step2)
		Phase.EXIT:
			# Accelerate up and off the top of the screen.
			_vel = min(_vel + exit_accel * delta, exit_max_speed)
			return Vector2(0, -_vel * delta)
	return Vector2.ZERO
