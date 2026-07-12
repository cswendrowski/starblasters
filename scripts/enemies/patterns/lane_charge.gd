extends "res://scripts/enemies/movement_pattern.gd"

# Lane charger (Roman 2026-06-08). Comes into the lane SLOWLY (a readable telegraph),
# then the moment it crosses into the firing/engagement zone it rapidly ACCELERATES
# straight down and rushes the exit — a slow wind-up followed by a committed dive.
#
# Monotonic descent, so it's path-phase-capable (a weapon, if any, fires on band-Y).

@export var drift_x: float = 0.0
# Locomotion refactor 2026-06-19: the chassis move_speed IS the committed CHARGE speed.
# The telegraph entry is ABSOLUTE (1 px/f), not a fraction of the charge — a ratio collapses
# below the clarity creep floor on slow chassis (120 px/s chassis → 17 px/s entry crawl),
# and it must never drop under Clarity's 30 px/s creep rung or exceed the charge itself.
const ENTER_SPEED: float = 60.0                  # px/s — deliberate 1 px/f telegraph entry
const CHARGE_ACCEL_RATIO: float = 700.0 / 600.0  # charge ramp as a multiple of enemy.accel

var _vy: float = 0.0
var _charging: bool = false


func _enter_speed(enemy) -> float:
	return clampf(ENTER_SPEED, 30.0, _move_speed(enemy))


func on_start(enemy) -> void:
	_vy = _enter_speed(enemy)
	_charging = false


func compute_step(enemy, delta: float) -> Vector2:
	var charge_speed: float = _move_speed(enemy)
	# Trigger the charge once the hull enters the engagement band.
	if not _charging and Zones.in_engagement(enemy.position.y):
		_charging = true
	if _charging:
		_vy = minf(_vy + _accel(enemy) * CHARGE_ACCEL_RATIO * delta, charge_speed)
	else:
		_vy = _enter_speed(enemy)
	return Vector2(drift_x, _vy) * delta


func path_phase_capable() -> bool:
	return true  # pure descent — band-Y is monotonic
