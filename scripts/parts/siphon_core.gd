extends "res://scripts/parts/module_part.gd"

# Siphon Core — sustain Module (2026-06-13). Every Nth kill restores one shield charge,
# N shrinking as you upgrade it (Mk.1 = every 10 kills … Mk.9 = every 2). Restores
# SHIELD charge only — never Mode Energy (spec §8: that's the runaway lever). Default-
# safe: module_siphon_kills_per_charge (0 = off) until this applies. The player's
# on_enemy_killed() drives the counter (main.gd pings it on each enemy death).


func _init() -> void:
	super._init()
	module_id = "siphon_core"
	display_name = "Siphon Core"
	description = "Every Nth kill restores a shield charge (Mk.1: every 10 → Mk.9: every 2). Rewards aggressive play with staying power."


# Kills needed per restored charge — 10 at Mk.1 down to 2 at Mk.9.
func _kills_per_charge() -> int:
	return maxi(2, 10 - (clampi(int(mark), 1, 9) - 1))


func apply(ship) -> void:
	if "module_siphon_kills_per_charge" in ship:
		# Best (lowest) threshold wins if somehow stacked; 0 means "off".
		var cur: int = int(ship.module_siphon_kills_per_charge)
		var mine: int = _kills_per_charge()
		ship.module_siphon_kills_per_charge = mine if cur <= 0 else mini(cur, mine)


func unapply(ship) -> void:
	if "module_siphon_kills_per_charge" in ship:
		ship.module_siphon_kills_per_charge = 0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var kills: int = _kills_per_charge() if m == int(mark) else maxi(2, 10 - (m - 1))
	return "Refunds a shield charge every %d kills" % kills
