extends "res://scripts/parts/module_part.gd"

# Corpo Shield Core (2026-07-11) — the mass-produced Ultra Galactic counterpart to the
# vintage Free Systems Shield Core. Half the charge capacity (base 5, +1 per Mk, +2 at
# Mk.9 → Mk.9 = 15, exactly half the vintage core's curve) but built to CHARGE FAST:
# a shorter post-hit regen delay AND a quicker per-charge tick, applied min-wins onto
# the ship's shield_regen_delay / shield_regen_interval (same convention as the Shield
# Capacitor, which still stacks on top for vintage-core builds — its Mk.9 floor stays
# lower, so it isn't obsoleted).
#
# Like the vintage core, its PRESENCE is what grants a shield at all (module_shield_base,
# max-wins). Default kit on the corpo hulls (Wraith / Weaver); rolls in the outpost shop.
# See docs/ship_starting_loadouts_2026-07-11.md.


func _init() -> void:
	super._init()
	module_id = "shield_core_corpo"
	display_name = "Corpo Shield Core"
	description = "A mass-produced Ultra Galactic shield core built to charge quickly — but without the particle density or charge capacity of a vintage Free Systems core. 5 charges base (+1 per Mk), recharging sooner and faster after a hit."
	# Effective worth ≈ 5 hull-pips-equivalent + the regen premium (≈ RH Mk.5 = 396;
	# see docs/ship_starting_loadouts_2026-07-11.md) — priced under the vintage core.
	shop_base_cost = 380
	shop_cost_per_mk = 90


# Base charge pool this core powers (player.apply_run_upgrades / outpost card).
func base_charges() -> int:
	return 5


# Shield capacity ABOVE the base 5: +1 per Mk, +2 extra at Mk.9 (half the vintage curve).
func _capacity_bonus() -> int:
	return (clampi(int(mark), 1, 9) - 1) + (2 if int(mark) >= 9 else 0)


# Regen numbers (Mk.1 = 3.0s delay / 0.6s per charge → Mk.9 = 1.5s / 0.35s; ship base is
# 5.0s / 1.0s). Public reads so the outpost Shield stat card shows the LIVE values.
func regen_delay() -> float:
	return maxf(1.5, 3.0 - float(clampi(int(mark), 1, 9) - 1) * 0.2)


func regen_interval() -> float:
	return maxf(0.35, 0.6 - float(clampi(int(mark), 1, 9) - 1) * 0.03)


func apply(ship) -> void:
	if "module_shield_base" in ship:
		ship.module_shield_base = maxi(int(ship.module_shield_base), base_charges())
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus += _capacity_bonus()
	# Best (lowest) value wins if stacked with a Shield Capacitor; ship defaults are 5s / 1s.
	if "shield_regen_delay" in ship:
		ship.shield_regen_delay = minf(float(ship.shield_regen_delay), regen_delay())
	if "shield_regen_interval" in ship:
		ship.shield_regen_interval = minf(float(ship.shield_regen_interval), regen_interval())


func unapply(ship) -> void:
	# Blunt resets, matching shield_capacitor's unapply convention.
	if "module_shield_base" in ship:
		ship.module_shield_base = 0
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus -= _capacity_bonus()
	if "shield_regen_delay" in ship:
		ship.shield_regen_delay = 5.0
	if "shield_regen_interval" in ship:
		ship.shield_regen_interval = 1.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var bonus: int = (m - 1) + (2 if m >= 9 else 0)
	var delay: float = maxf(1.5, 3.0 - float(m - 1) * 0.2)
	var interval: float = maxf(0.35, 0.6 - float(m - 1) * 0.03)
	return "Shield charges: +%d (base %d) · regen %.1fs delay, %.2fs/charge" % [bonus, base_charges(), delay, interval]
