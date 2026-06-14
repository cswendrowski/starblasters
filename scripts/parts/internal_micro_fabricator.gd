extends "res://scripts/parts/module_part.gd"

# Internal Micro Fabricator — logistics Module (2026-06-14). Clearing a combat level
# restocks a % of MAX ammo for your metered primary + secondary weapons (capped at max,
# never exceeds). The restock fires in main._on_level_cleared via Run.restock_ammo_fraction,
# topping up the persistent pools that carry to the next level. Mk adds 5% per mark.
# Default-safe: module_ammo_restore_pct stays 0 unless equipped. No effect on infinite
# blasters / unmetered secondaries (nothing to restock).

@export var base_pct: float = 0.05      # Mk.1 = 5% of max ammo restocked per clear
@export var pct_per_mark: float = 0.05  # +5% per Mk


func _init() -> void:
	super._init()
	module_id = "micro_fabricator"
	display_name = "Internal Micro Fabricator"
	description = "Clearing a level fabricates ammo: restocks a slice of your max primary + secondary ammo (never past max). Mk adds 5% per mark."


func apply(ship) -> void:
	# Best-wins: never lower an already-stronger fabricator from another source.
	ship.module_ammo_restore_pct = maxf(ship.module_ammo_restore_pct, _pct_for(int(mark)))


func unapply(ship) -> void:
	ship.module_ammo_restore_pct = 0.0


func _pct_for(at_mark: int) -> float:
	return base_pct + (at_mark - 1) * pct_per_mark


# Editor readout — restock fraction (as a whole %) at this Mk.
func effective_damage(at_mark: int) -> int:
	return int(round(_pct_for(at_mark) * 100.0))
