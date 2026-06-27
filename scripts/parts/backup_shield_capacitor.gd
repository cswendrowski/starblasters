extends "res://scripts/parts/module_part.gd"

# Backup Shield Capacitor — defensive Module (2026-06-14). The FIRST time your shield
# drops in a combat level, an emergency cell dumps a % of your max shield charges back
# in (capped at max). Once per level — the player.gd `_backup_cap_used` flag resets in
# start(). Mk raises the restored fraction by 5% per mark.
# Default-safe: module_backup_shield_pct stays 0 unless equipped.

@export var base_pct: float = 0.05      # Mk.1 = 5% of max shield restored
@export var pct_per_mark: float = 0.05  # +5% per Mk

var _applied_pct: float = 0.0


func _init() -> void:
	super._init()
	module_id = "backup_shield_capacitor"
	display_name = "Backup Shield Capacitor"
	description = "The first time your shield drops in a level, instantly restore a slice of your max shield charges. Once per level. Mk improves the restore by 5%."


func apply(ship) -> void:
	_applied_pct = base_pct + (int(mark) - 1) * pct_per_mark
	# Best-wins: never lower an already-stronger capacitor from another source.
	ship.module_backup_shield_pct = maxf(ship.module_backup_shield_pct, _applied_pct)


func unapply(ship) -> void:
	ship.module_backup_shield_pct = 0.0
	_applied_pct = 0.0


# Editor readout — restored fraction (as a whole %) at this Mk.
func effective_damage(at_mark: int) -> int:
	return int(round((base_pct + (at_mark - 1) * pct_per_mark) * 100.0))


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var pct: int = int(round((base_pct + (m - 1) * pct_per_mark) * 100.0))
	return "Once per level, restores %d%% of max shield" % pct
