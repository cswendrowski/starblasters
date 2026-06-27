extends "res://scripts/parts/module_part.gd"

# Repair Nanites — defensive Module (2026-06-13). Reifies in-combat hull regen as a bay
# choice (distinct from the between-node Self-Repair upgrade). After a few seconds
# undamaged it regrows hull, gated just short of full so it rewards disengaging without
# trivializing damage. Default-safe: ship.module_regen_interval (0) is off until applied.
#   Mk.1 = a pip every 12s  →  Mk.9 = every 4s.


func _init() -> void:
	super._init()
	module_id = "repair_nanites"
	display_name = "Repair Nanites"
	description = "Regrows hull in combat after a few seconds undamaged (Mk.1: a pip every 12s → Mk.9: every 4s). Caps just short of full."


# Seconds per +1 hull pip — 12 at Mk.1 down to 4 at Mk.9.
func _interval() -> float:
	return float(maxi(4, 12 - (clampi(int(mark), 1, 9) - 1)))


func apply(ship) -> void:
	if "module_regen_interval" in ship:
		var cur: float = float(ship.module_regen_interval)
		var mine: float = _interval()
		ship.module_regen_interval = mine if cur <= 0.0 else minf(cur, mine)


func unapply(ship) -> void:
	if "module_regen_interval" in ship:
		ship.module_regen_interval = 0.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var interval: float = float(maxi(4, 12 - (m - 1)))
	return "Repairs 1 hull every %.0fs" % interval
