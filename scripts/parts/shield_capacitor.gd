extends "res://scripts/parts/module_part.gd"

# Shield Capacitor — defensive Module (2026-06-13). Speeds your shield back up: a SHORTER
# delay before regen begins (base 5s) AND a FASTER per-charge tick (base 1s). Pairs with
# the Shield Core for a tanky, self-sustaining build. Default-safe — the player's
# shield_regen_delay / shield_regen_interval default to the base 5s / 1s until this applies.
#   Mk.1 = 4.5s delay, 0.93s/charge  →  Mk.9 = 1.0s delay, 0.37s/charge.


func _init() -> void:
	super._init()
	module_id = "shield_capacitor"
	display_name = "Shield Capacitor"
	description = "Recharges your shield faster and sooner — shorter delay after a hit + a quicker per-charge tick. Mk.1: 4.5s/0.9s → Mk.9: 1.0s/0.4s."


func _delay() -> float:
	return maxf(1.0, 5.0 - float(clampi(int(mark), 1, 9)) * 0.5)


func _interval() -> float:
	return maxf(0.3, 1.0 - float(clampi(int(mark), 1, 9)) * 0.07)


func apply(ship) -> void:
	# Best (lowest) value wins if stacked; the ship's defaults are the base 5s / 1s.
	if "shield_regen_delay" in ship:
		ship.shield_regen_delay = minf(float(ship.shield_regen_delay), _delay())
	if "shield_regen_interval" in ship:
		ship.shield_regen_interval = minf(float(ship.shield_regen_interval), _interval())


func unapply(ship) -> void:
	if "shield_regen_delay" in ship:
		ship.shield_regen_delay = 5.0
	if "shield_regen_interval" in ship:
		ship.shield_regen_interval = 1.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var delay: float = maxf(1.0, 5.0 - float(m) * 0.5)
	var interval: float = maxf(0.3, 1.0 - float(m) * 0.07)
	return "Shield recharges %.1fs sooner, every %.1fs" % [5.0 - delay, interval]
