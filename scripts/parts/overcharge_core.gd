extends "res://scripts/parts/module_part.gd"

# Overcharge Core — risk/reward offensive Module (2026-06-13). Boosts primary damage
# but costs you one max shield charge — push your damage at the price of survivability
# (and a natural pairing with the shieldless Shield-Core-dropped build). Default-safe:
# the ship's module_damage_mult (1.0) + module_shield_charge_penalty (0) are no-ops
# until this applies.
#   Mk.1 = +10% damage  →  Mk.9 = +30% (+2.5%/Mk).  Always −1 max shield charge.


func _init() -> void:
	super._init()
	module_id = "overcharge_core"
	display_name = "Overcharge Core"
	description = "+10% primary damage (more per Mk), but −1 max shield charge. For builds that trade armor for teeth."


# +10% at Mk.1 climbing to +30% at Mk.9.
func _damage_mult() -> float:
	return 1.10 + 0.025 * float(clampi(int(mark), 1, 9) - 1)


func apply(ship) -> void:
	if "module_damage_mult" in ship:
		ship.module_damage_mult *= _damage_mult()
	if "module_shield_charge_penalty" in ship:
		ship.module_shield_charge_penalty += 1


func unapply(ship) -> void:
	if "module_damage_mult" in ship:
		ship.module_damage_mult /= _damage_mult()
	if "module_shield_charge_penalty" in ship:
		ship.module_shield_charge_penalty -= 1
