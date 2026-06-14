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
	if int(mark) >= 9 and "module_hull_repair_discount" in ship:
		ship.module_hull_repair_discount = 0.30


func unapply(ship) -> void:
	if "module_hull_bonus" in ship:
		ship.module_hull_bonus -= _pips()
	if "module_hull_repair_discount" in ship:
		ship.module_hull_repair_discount = 0.0
