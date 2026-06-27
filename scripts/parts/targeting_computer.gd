extends "res://scripts/parts/module_part.gd"

# Targeting Computer — offensive Module (2026-06-13). Gives primary fire a chance to
# CRIT for ×2 damage; crit bolts flash purple (player.gd MODULE_CRIT_COLOR). Rolled
# once per trigger so a crit reads as a whole purple burst. Default-safe:
# ship.module_crit_chance (0) is off until applied.
#   Mk.1 = 10% crit  →  Mk.9 = 30%.


func _init() -> void:
	super._init()
	module_id = "targeting_computer"
	display_name = "Targeting Computer"
	description = "Primary shots have a chance to crit for ×2 damage — crit bolts streak purple. Mk.1: 10% → Mk.9: 30%."


func _crit_chance() -> float:
	return 0.10 + 0.025 * float(clampi(int(mark), 1, 9) - 1)


func apply(ship) -> void:
	if "module_crit_chance" in ship:
		ship.module_crit_chance = maxf(float(ship.module_crit_chance), _crit_chance())


func unapply(ship) -> void:
	if "module_crit_chance" in ship:
		ship.module_crit_chance = 0.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var chance: float = 0.10 + 0.025 * float(m - 1)
	var pct: int = int(round(chance * 100.0))
	return "+%d%% critical-hit chance (×2 damage)" % pct
