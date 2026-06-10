extends "res://scripts/parts/metered_primary.gd"

# Minigun Cannon. Hitscan rapid-fire energy weapon. Ammo + mark progression
# mirrors the Machinegun Cannon (Mk.1=1000, compound +20%/Mk ≈ Mk.9~4300).
# Rate of fire matches Rotary Laser (0.05s cooldown = 20 shots/sec).
# Each shot is a hitscan that damages the FIRST enemy in the vertical column
# above the player, with a minigun_tracer sprite drawn as visual feedback.
# Uses Machinegun Cannon's muzzle flash + shell eject (orange + smoke + shell).

@export var cooldown_at_mk9: float = 0.05  # Match Rotary Laser rate (20 shots/sec)


func _init() -> void:
	super._init()
	display_name = "Minigun"
	description = "Rapid hitscan energy cannon. Mk.1: 1000 rounds at 1200 RPM. Mk.9: ~4300 rounds. Fires instantly on press."
	base_damage = 5
	dmg_per_mark = 0
	base_cooldown = 0.05
	base_ammo = 1000
	refill_cost_override = 100


func _weapon_style() -> int:
	return WS.WeaponStyle.MINIGUN


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.MINIGUN


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [5, 5],  # fixed
		"cooldown": [base_cooldown, cooldown_at_mk9],
	}


func ammo_at_mark(mk: int) -> int:
	# Compound +20% per mark: Mk1=1000, Mk9≈4300.
	return int(1000.0 * pow(1.2, float(mk - 1)))
