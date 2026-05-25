extends "res://scripts/parts/bullet_secondary.gd"

# Rocket Pod. Secondary weapon (HARDPOINT_WING). Dumb-fire ordnance —
# fast, straight-line, contact-detonate. Slow cadence balances the high
# per-shot damage; doesn't home, so the player has to lead targets.


func _init() -> void:
	super._init()
	display_name = "Rocket Pod"
	description = "Dumb-fire rockets. Heavy hit, lead your shots. Secondary."
	base_damage = 2
	dmg_per_mark = 2
	base_cooldown = 0.55


func _base_ammo() -> int:
	return 60


func _homing() -> bool:
	return false
