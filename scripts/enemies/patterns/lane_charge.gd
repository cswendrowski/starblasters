extends "res://scripts/enemies/movement_pattern.gd"

# Lane charger (Roman 2026-06-08). Comes into the lane SLOWLY (a readable telegraph),
# then the moment it crosses into the firing/engagement zone it rapidly ACCELERATES
# straight down and rushes the exit — a slow wind-up followed by a committed dive.
#
# Monotonic descent, so it's path-phase-capable (a weapon, if any, fires on band-Y).

@export var drift_x: float = 0.0
# Locomotion refactor 2026-06-19: the chassis move_speed IS the committed CHARGE speed; the slow
# telegraph entry is a fixed fraction of it, so the "slow wind-up → fast commit" character scales
# with the enemy (a fast hull still telegraphs, then rushes at its full speed). The *_speed exports
# above are vestigial.
const ENTER_RATIO: float = 60.0 / 420.0          # slow entry as a fraction of the charge speed
const CHARGE_ACCEL_RATIO: float = 700.0 / 600.0  # charge ramp as a multiple of enemy.accel

var _vy: float = 0.0
var _charging: bool = false


func on_start(enemy) -> void:
	_vy = _move_speed(enemy) * ENTER_RATIO
	_charging = false


func compute_step(enemy, delta: float) -> Vector2:
	var charge_speed: float = _move_speed(enemy)
	# Trigger the charge once the hull enters the engagement band.
	if not _charging and Zones.in_engagement(enemy.position.y):
		_charging = true
	if _charging:
		_vy = minf(_vy + _accel(enemy) * CHARGE_ACCEL_RATIO * delta, charge_speed)
	else:
		_vy = charge_speed * ENTER_RATIO
	return Vector2(drift_x, _vy) * delta


func path_phase_capable() -> bool:
	return true  # pure descent — band-Y is monotonic
