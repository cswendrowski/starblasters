extends "res://scripts/enemies/movement_pattern.gd"

# Lane charger (Roman 2026-06-08). Comes into the lane SLOWLY (a readable telegraph),
# then the moment it crosses into the firing/engagement zone it rapidly ACCELERATES
# straight down and rushes the exit — a slow wind-up followed by a committed dive.
#
# Monotonic descent, so it's path-phase-capable (a weapon, if any, fires on band-Y).

@export var enter_speed: float = 60.0        # 1 px/f — slow, deliberate entry
@export var charge_accel: float = 700.0      # px/s^2 ramp once triggered
@export var charge_max_speed: float = 420.0  # 7 px/f rush (telegraphed by the slow entry)
@export var drift_x: float = 0.0

var _vy: float = 0.0
var _charging: bool = false


func on_start(_enemy) -> void:
	_vy = enter_speed
	_charging = false


func compute_step(enemy, delta: float) -> Vector2:
	# Trigger the charge once the hull enters the engagement band.
	if not _charging and Zones.in_engagement(enemy.position.y):
		_charging = true
	if _charging:
		_vy = minf(_vy + charge_accel * delta, charge_max_speed)
	else:
		_vy = enter_speed
	return Vector2(drift_x, _vy) * delta


func path_phase_capable() -> bool:
	return true  # pure descent — band-Y is monotonic
