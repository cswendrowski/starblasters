extends "res://scripts/enemies/movement_pattern.gd"

# Skirmisher (m6 §13): dive to advance_y, hold/fire briefly, retreat toward the
# top, repeat; on the LAST cycle, do a brief in-place jiggle telegraph and then
# accelerate up and off the top.
#
# Pattern pass:
# - 2026-06-05: eased endpoints; exit = up & off (was a sideways break).
# - 2026-06-06 (Roman): slower overall; the hold is no longer a dead stop (gentle
#   jiggle, randomized per instance); the EXIT no longer hitches — instead of
#   retreat→snap→re-accelerate (a velocity discontinuity), the final departure is
#   HOLD → PREP (a brief wind-up jiggle) → EXIT accelerating up FROM REST, so the
#   launch is smooth. Holds use absolute repositioning (anchor + offset) = no drift.

# 320×400 res rework: halved. Speeds retuned slower in EnemyRoster.make_movement.
@export var advance_y: float = 192.0
@export var hold_time: float = 0.6
@export var advance_speed: float = 110.0   # cruise speed (descending)
@export var retreat_speed: float = 150.0   # cruise speed (ascending, mid cycles)
@export var cycles: int = 2

# Endpoint easing: accelerate out of a turn at `accel`; decelerate over the last
# `decel_dist` px into an endpoint. `endpoint_min_speed` floors the eased target
# so the approach doesn't crawl asymptotically (Zeno) — kept low for a soft stop.
@export var accel: float = 360.0
@export var decel_dist: float = 44.0
@export var endpoint_min_speed: float = 22.0

# In-place liveliness: a gentle jiggle during HOLD, and a slightly larger one
# during PREP (the wind-up telegraph just before the ship bugs out).
@export var hold_jiggle_amp: float = 2.0
@export var prep_jiggle_amp: float = 3.5
@export var jiggle_freq: float = 1.1       # Hz
@export var prep_time: float = 0.45        # wind-up duration before EXIT

# Exit: accelerate upward off the top, from rest (smooth launch).
@export var exit_accel: float = 420.0
@export var exit_max_speed: float = 460.0

signal phase_entered(phase_name: String)

enum Phase { ADVANCE, HOLD, RETREAT, PREP, EXIT }
var _phase: int = Phase.ADVANCE
var _t: float = 0.0
var _cycle: int = 0
var _vel: float = 0.0
var _jt: float = 0.0                  # jiggle clock (HOLD / PREP)
var _anchor: Vector2 = Vector2.ZERO   # captured on HOLD/PREP entry
# Per-instance jiggle randomization so a row of Skirmishers desyncs.
var _phase_jx: float = 0.0
var _phase_jy: float = 0.0
var _freq_mul: float = 1.0

const TOP_Y := 24.0


func on_start(enemy) -> void:
	# Exit is upward off the top — needs FREE_ANY_EDGE so it despawns there
	# (CYCLE_BOTTOM never frees the top edge). Guarded so the visualizer's
	# bare dummy (no offscreen_mode property) doesn't choke.
	if "offscreen_mode" in enemy:
		enemy.offscreen_mode = 1  # EnemyBase.OffscreenMode.FREE_ANY_EDGE
	_phase = Phase.ADVANCE
	_t = 0.0
	_cycle = 0
	_vel = 0.0
	_jt = 0.0
	_phase_jx = randf() * TAU
	_phase_jy = randf() * TAU
	_freq_mul = randf_range(0.85, 1.15)
	phase_entered.emit("advance")


# Eased speed toward an endpoint `dist` px away: cruise far out, ramp down inside
# decel_dist, floored at endpoint_min_speed so the snap actually lands.
func _eased(cruise: float, dist: float) -> float:
	var t: float = cruise * clampf(dist / decel_dist, 0.0, 1.0)
	return maxf(t, endpoint_min_speed)


# Absolute jiggle offset, centered so it is (0,0) at _jt == 0 (no pop on entry).
func _jiggle_off(amp: float) -> Vector2:
	var oy: float = amp * (sin(_jt * jiggle_freq * _freq_mul * TAU + _phase_jy) - sin(_phase_jy))
	var ox: float = (amp * 0.6) * (sin(_jt * jiggle_freq * _freq_mul * 0.7 * TAU + _phase_jx) - sin(_phase_jx))
	return Vector2(ox, oy)


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ADVANCE:
			var dist: float = advance_y - enemy.position.y
			_vel = move_toward(_vel, _eased(advance_speed, dist), accel * delta)
			var step: float = _vel * delta
			if enemy.position.y + step >= advance_y:
				step = advance_y - enemy.position.y
				_enter_hold(enemy)
			return Vector2(0, step)
		Phase.HOLD:
			_t += delta
			_jt += delta
			if _t >= hold_time:
				if _cycle + 1 >= cycles:
					# Last cycle: wind up in place, then leave (no retreat-snap).
					_phase = Phase.PREP
					_t = 0.0
					_jt = 0.0
					_anchor = enemy.position
					phase_entered.emit("prep")
				else:
					_phase = Phase.RETREAT
					_vel = 0.0
					phase_entered.emit("retreat")
				return _anchor - enemy.position  # settle back to anchor cleanly
			return (_anchor + _jiggle_off(hold_jiggle_amp)) - enemy.position
		Phase.RETREAT:
			var dist2: float = enemy.position.y - TOP_Y
			_vel = move_toward(_vel, _eased(retreat_speed, dist2), accel * delta)
			var step2: float = -_vel * delta
			if enemy.position.y + step2 <= TOP_Y:
				step2 = TOP_Y - enemy.position.y
				_cycle += 1
				_vel = 0.0
				_phase = Phase.ADVANCE
				phase_entered.emit("advance")
			return Vector2(0, step2)
		Phase.PREP:
			_t += delta
			_jt += delta
			if _t >= prep_time:
				_phase = Phase.EXIT
				_vel = 0.0
				phase_entered.emit("exit")
				return _anchor - enemy.position
			return (_anchor + _jiggle_off(prep_jiggle_amp)) - enemy.position
		Phase.EXIT:
			# Accelerate up and off the top, from rest — smooth launch.
			_vel = min(_vel + exit_accel * delta, exit_max_speed)
			return Vector2(0, -_vel * delta)
	return Vector2.ZERO


func _enter_hold(enemy) -> void:
	_phase = Phase.HOLD
	_t = 0.0
	_jt = 0.0
	_vel = 0.0
	_anchor = Vector2(enemy.position.x, advance_y)
	phase_entered.emit("hold")
