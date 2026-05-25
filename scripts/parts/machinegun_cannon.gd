extends "res://scripts/parts/metered_primary.gd"

# Machinegun Cannon. Alt CANNON weapon. Trades the Energy Blaster's
# infinite ammo for raw damage + cadence: limited ammo (1000 rounds at
# Mk.1), tighter cooldown, brrrt audio loop. Purchasable cheap at Friendly
# Outposts; ammo refills available there and at Junk Trader signal events.


func _init() -> void:
	super._init()
	display_name = "Machinegun Cannon"
	description = "High rate of fire, high damage. Limited ammo (1000 rounds). Refill at outposts."
	base_damage = 1
	dmg_per_mark = 1
	base_cooldown = 0.10
	base_ammo = 1000


func _weapon_style() -> int:
	return WS.WeaponStyle.MACHINEGUN
