extends "res://scripts/parts/machinegun_cannon.gd"

# Autocannon Cannon. Replaces the Machinegun Cannon. Same projectiles, damage,
# muzzle flash, and scaling as the machinegun. Adds a spin-up mechanic:
# 1.5s delay from fire_held to actual firing, playing autocannon_start.ogg.
# When firing stops (fire_held = false), plays autocannon_stop.ogg.
# Re-pressing fire restarts the full 1.5s spin-up cycle.

func _init() -> void:
	super._init()
	display_name = "Autocannon"
	description = "Cannon with spin-up delay. Same ammo and damage as Machinegun. Press to spin (1.5s), then fires at full rate."


func _weapon_style() -> int:
	return WS.WeaponStyle.AUTOCANNON


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.AUTOCANNON
