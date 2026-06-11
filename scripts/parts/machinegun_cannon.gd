extends "res://scripts/parts/metered_primary.gd"

# Machinegun Cannon. Alt CANNON weapon. Fixed damage (5), cadence scales
# from 450 RPM (Mk.1) to 600 RPM (Mk.9). Ammo scales compound +20%/Mk
# (Mk.1=1000, Mk.9≈4300). Refill at outposts costs 100 bounty (double
# the standard rate — MG eats rounds fast).

@export var cooldown_at_mk9: float = 0.10


func _init() -> void:
	super._init()
	display_name = "Machinegun Cannon"
	description = "High rate of fire, fixed damage 5. Mk.1: 1000 rounds at 450 RPM. Mk.9: ~4300 rounds at 600 RPM. Refill at outposts (100)."
	# Stats live in the subclass .tres (autocannon.tres etc.) — single source of truth.


func _weapon_style() -> int:
	return WS.WeaponStyle.MACHINEGUN


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [5, 5],  # fixed
		"cooldown": [base_cooldown, cooldown_at_mk9],
	}


func ammo_at_mark(mk: int) -> int:
	# Compound +20% per mark: Mk1=1000, Mk9≈4300.
	return int(1000.0 * pow(1.2, float(mk - 1)))
