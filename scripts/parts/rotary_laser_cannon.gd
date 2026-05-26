extends "res://scripts/parts/metered_primary.gd"

# Rotary Laser Cannon. Minigun-style energy weapon — blistering rate of fire
# (20 shots/sec), limited ammo (120 base + 30/Mk), recharges at 3 shots/sec
# when not firing. Pairs with the ROTARY_LASER weapon_style branch in player.gd.
# No outpost refill — natural recharge makes sold refills redundant.


func _init() -> void:
	super._init()
	display_name = "Rotary Laser"
	description = "Rapid-fire energy cannon. Mk.1: 120 ammo, recharges 3/sec. Each Mk adds 30 ammo."
	base_damage = 1
	dmg_per_mark = 0
	base_cooldown = 0.05
	base_ammo = 120
	ammo_recharge_rate = 3.0
	no_outpost_refill = true


func ammo_at_mark(mk: int) -> int:
	return 120 + 30 * (mk - 1)


func _weapon_style() -> int:
	return WS.WeaponStyle.ROTARY_LASER


func _apply_visuals(ship) -> void:
	# Seed the per-mark ammo BEFORE super so metered_primary._apply_visuals
	# reads the correct current_ammo value (not the stale -1 default).
	current_ammo = ammo_at_mark(int(mark))
	super._apply_visuals(ship)
	# Overwrite ammo_max after super (super writes base_ammo = 120 flat).
	if "ammo_max" in ship:
		ship.ammo_max = ammo_at_mark(int(mark))
