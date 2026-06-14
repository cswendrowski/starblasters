extends "res://scripts/parts/module_part.gd"

# Thrusters — utility Module (2026-06-13, the former Thrusters upgrade reified). +move
# speed on top of your engine. Default-safe (module_speed_pct 0 = engine speed only).
#   Mk.1 = +3%  →  Mk.9 = +27% (the player still clamps to the clarity ceiling).


func _init() -> void:
	super._init()
	module_id = "thrusters"
	display_name = "Thrusters"
	description = "Auxiliary thrusters — +3% move speed per Mk (up to +27%) on top of your engine."


func _speed_pct() -> float:
	return float(clampi(int(mark), 1, 9)) * 0.03


func apply(ship) -> void:
	if "module_speed_pct" in ship:
		ship.module_speed_pct += _speed_pct()


func unapply(ship) -> void:
	if "module_speed_pct" in ship:
		ship.module_speed_pct -= _speed_pct()
