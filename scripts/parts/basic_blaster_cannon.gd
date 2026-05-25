extends "res://scripts/parts/primary_weapon.gd"

# Energy Blaster. Default ship-issued primary cannon. Blue energy bolts,
# infinite ammo, modest damage. Reference balance weapon.
# Mk.1=2, +2/Mk → Mk.9=18.


func _init() -> void:
	super._init()
	display_name = "Energy Blaster"
	description = "Standard issue energy cannon. Unlimited ammo."
	base_damage = 2
	dmg_per_mark = 2
	base_cooldown = 0.22


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_SMALL
