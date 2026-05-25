extends "res://scripts/parts/metered_primary.gd"

# Rotary Laser Cannon. Minigun-style energy weapon — blistering rate of fire
# (20 shots/sec), limited ammo (300 base), recharges at 10 shots/sec when not
# firing. Pairs with the ROTARY_LASER weapon_style branch in player.gd.


func _init() -> void:
	super._init()
	display_name = "Rotary Laser"
	description = "Rapid-fire energy cannon. 300 ammo base; recharges when not firing."
	base_damage = 1
	dmg_per_mark = 1
	base_cooldown = 0.05
	base_ammo = 300
	ammo_recharge_rate = 10.0


func _weapon_style() -> int:
	return WS.WeaponStyle.ROTARY_LASER
