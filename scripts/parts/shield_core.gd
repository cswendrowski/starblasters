extends "res://scripts/parts/module_part.gd"

# Shield Core — the reified shield, as a passive Module (2026-06-13). Its PRESENCE is what
# gives you a shield at all: drop it for a free bay slot and you fly shieldless — the
# glass-cannon build. Its Mk drives the shield CAPACITY (the old Shield Capacity upgrade
# folded in 2026-06-13): base 10 charges, +2 per Mk, +4 at Mk.9 → Mk.1 = 10, Mk.9 = 30.
#
# 2026-07-11 (Corpo Shield Core split): the base charge count is PART-DRIVEN now —
# apply() writes module_shield_base (max-wins across cores) instead of the player
# hardcoding 10; player.apply_run_upgrades assembles base + Mk bonuses. This vintage
# Free Systems core is the 10-charge original; the mass-produced Corpo core
# (corpo_shield_core.gd) is the 5-charge fast-recharge variant. Both shop-priced via
# the Part shop_base_cost/shop_cost_per_mk overrides (a core is worth ~7 Reinforced
# Hull Mks of durability, not a flat-116 module).


func _init() -> void:
	super._init()
	module_id = "shield_core"
	display_name = "Shield Core"
	description = "An old, rare, and powerful shield core built by the Free Systems military — unmatched protection for its form factor (10 charges base, +2 per Mk). They really aren't built like this any more. Drop it for a free module slot and fly shieldless."
	# Effective worth ≈ 10 hull pips ≈ Reinforced Hull Mk.7 (see
	# docs/ship_starting_loadouts_2026-07-11.md valuation) — priced accordingly.
	shop_base_cost = 520
	shop_cost_per_mk = 140


# Base charge pool this core powers (player.apply_run_upgrades reads it via
# module_shield_base; the outpost Shield stat card reads it directly).
func base_charges() -> int:
	return 10


# Shield capacity ABOVE the base 10 (assembled in player.apply_run_upgrades).
func _capacity_bonus() -> int:
	return (clampi(int(mark), 1, 9) - 1) * 2 + (4 if int(mark) >= 9 else 0)


func apply(ship) -> void:
	# Base is max-wins across equipped cores (bases don't sum); Mk bonuses DO stack.
	if "module_shield_base" in ship:
		ship.module_shield_base = maxi(int(ship.module_shield_base), base_charges())
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus += _capacity_bonus()


func unapply(ship) -> void:
	# Blunt base reset (same convention as shield_capacitor's unapply): a second
	# equipped core's base is lost until the next apply pass rebuilds the fields.
	if "module_shield_base" in ship:
		ship.module_shield_base = 0
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus -= _capacity_bonus()


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var bonus: int = _capacity_bonus() if m == int(mark) else ((m - 1) * 2 + (4 if m >= 9 else 0))
	return "Shield charges: +%d (base %d)" % [bonus, base_charges()]
