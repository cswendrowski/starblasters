extends "res://scripts/parts/module_part.gd"

# Passive Energy Routers — defensive Module (2026-06-14). While you hold fire the shield
# regen runs at its normal (slow) cadence; stop shooting and rerouted power makes it kick
# in sooner AND tick faster. Concretely: when the primary trigger has been idle past the
# grace window, player.gd scales both the regen delay and the per-charge interval down by
# module_energy_router_pct (composes on top of the Shield Capacitor's base reduction).
# Mk deepens the idle boost by 5% per mark.
# Default-safe: module_energy_router_pct stays 0 unless equipped.

@export var base_pct: float = 0.20      # Mk.1 = 20% faster regen while idle
@export var pct_per_mark: float = 0.05  # +5% per Mk (→ 60% at Mk.9)


func _init() -> void:
	super._init()
	module_id = "energy_routers"
	display_name = "Passive Energy Routers"
	description = "Hold fire and your shield regen crawls; stop shooting and rerouted power makes it kick in sooner and tick faster. Mk deepens the idle boost."


func apply(ship) -> void:
	# Best-wins: keep the deepest boost if stacked.
	ship.module_energy_router_pct = maxf(ship.module_energy_router_pct, _pct_for(int(mark)))


func unapply(ship) -> void:
	ship.module_energy_router_pct = 0.0


func _pct_for(at_mark: int) -> float:
	return base_pct + (at_mark - 1) * pct_per_mark


# Editor readout — idle regen boost (as a whole %) at this Mk.
func effective_damage(at_mark: int) -> int:
	return int(round(_pct_for(at_mark) * 100.0))


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var pct: int = int(round(_pct_for(m) * 100.0))
	return "+%d%% shield regen speed when idle" % pct
