extends "res://scripts/parts/primary_weapon.gd"

# Energy Blaster. Default ship-issued primary cannon. Blue energy bolts,
# infinite ammo, modest damage. Reference balance weapon.
# Mk.1=2, +2/Mk → Mk.9=18.


func _init() -> void:
	super._init()
	display_name = "Energy Blaster"
	description = "Standard issue energy cannon. Unlimited ammo."
	# Stats live in resources/weapons/energy_blaster.tres (single source of truth).


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_SMALL


# Energy Blaster is the permanent core primary — infinite ammo always.
# Run.cannon_pool[0] is always this part; -1 signals "no metering".
func ammo_at_mark(_mk: int) -> int:
	return -1
