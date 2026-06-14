extends "res://scripts/parts/module_part.gd"

# Critical System De-Limiter — risk Module (2026-06-13, "Adrenal Surge" reframed). As
# your hull falls it lifts the safety limiters: fire-rate AND primary damage scale up,
# peaking at 1 hull. 0 bonus at full hull, so it only pays off when you're hurting — a
# comeback/glass-cannon enabler. Default-safe: ship.module_delimiter_max (0) is off until
# applied. The hull-fraction curve lives in player._delimiter_bonus().
#   Mk.1 = +25% at 1 hull  →  Mk.9 = +75%.


func _init() -> void:
	super._init()
	module_id = "system_delimiter"
	display_name = "Critical System De-Limiter"
	description = "Lifts the safety limiters as your hull falls — fire-rate and damage climb the closer to death you are, peaking at 1 hull. Mk.1: +25% → Mk.9: +75%."


func _max_bonus() -> float:
	return 0.25 + 0.0625 * float(clampi(int(mark), 1, 9) - 1)


func apply(ship) -> void:
	if "module_delimiter_max" in ship:
		ship.module_delimiter_max = maxf(float(ship.module_delimiter_max), _max_bonus())


func unapply(ship) -> void:
	if "module_delimiter_max" in ship:
		ship.module_delimiter_max = 0.0
