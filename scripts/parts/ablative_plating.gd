extends "res://scripts/parts/module_part.gd"

# Ablative Plating — defensive Module (2026-06-13). Reifies hull plating as a
# DETERMINISTIC shrug: it absorbs every Nth hull hit outright (no RNG, unlike the old
# hull_plating_mk shrug-chance — spec §15). Predictable mitigation you can build around.
# Default-safe: ship.module_ablative_n (0) is off until applied.
#   Mk.1 = absorb every 6th hull hit  →  Mk.9 = every 2nd.


func _init() -> void:
	super._init()
	module_id = "ablative_plating"
	display_name = "Ablative Plating"
	description = "Deterministically shrugs off every Nth hull hit — no RNG. Mk.1: every 6th → Mk.9: every 2nd."


# Absorb every Nth hull hit — 6 at Mk.1 down to 2 at Mk.9.
func _every_n() -> int:
	return maxi(2, 6 - (clampi(int(mark), 1, 9) - 1) / 2)


func apply(ship) -> void:
	if "module_ablative_n" in ship:
		var cur: int = int(ship.module_ablative_n)
		var mine: int = _every_n()
		ship.module_ablative_n = mine if cur <= 0 else mini(cur, mine)


func unapply(ship) -> void:
	if "module_ablative_n" in ship:
		ship.module_ablative_n = 0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var n: int = _every_n() if m == int(mark) else maxi(2, 6 - (m - 1) / 2)
	match n:
		2:
			return "Negates every 2nd hull hit"
		3:
			return "Negates every 3rd hull hit"
		4:
			return "Negates every 4th hull hit"
		5:
			return "Negates every 5th hull hit"
		_:
			return "Negates every %dth hull hit" % n
