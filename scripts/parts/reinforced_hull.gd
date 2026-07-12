extends "res://scripts/parts/module_part.gd"

# Reinforced Hull — defensive Module (2026-06-13, the former Hull upgrade reified). Adds
# hull pips on top of the base 2, capped at +8; Mk.9 also grants the −30% hull-repair
# discount the old Hull Mk.9 gave. Default-safe (module_hull_bonus 0 = base hull only).
#   Mk.1 = +1 pip  →  Mk.8 = +8  →  Mk.9 = +8 + repair discount.


func _init() -> void:
	super._init()
	module_id = "reinforced_hull"
	display_name = "Reinforced Hull"
	description = "Bolts on extra hull plating — +1 pip per Mk (up to +8). Mk.9 also makes repairs 30% cheaper."


func _pips() -> int:
	return mini(int(mark), 8)


func apply(ship) -> void:
	if "module_hull_bonus" in ship:
		ship.module_hull_bonus += _pips()


func unapply(ship) -> void:
	if "module_hull_bonus" in ship:
		ship.module_hull_bonus -= _pips()


# Mk.9 perk. Repairs happen at the OUTPOST, not in combat, so the discount is read
# straight off the module via Run.hull_repair_discount() (outpost._hull_repair_cost) —
# it never routes through the player ship.
func repair_discount() -> float:
	return 0.30 if int(mark) >= 9 else 0.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var pips: int = mini(m, 8)
	var desc: String = "+%d hull pip" % pips
	if pips != 1:
		desc += "s"
	if m >= 9:
		desc += ", repairs 30% cheaper at Mk.9"
	return desc
