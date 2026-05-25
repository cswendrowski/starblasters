extends "res://scripts/parts/bullet_secondary.gd"

# Seeking Missile launcher. Secondary weapon (HARDPOINT_WING) — fires
# alongside the primary cannon on its own cooldown. Slow cadence, slow
# projectile, but the missile homes onto the nearest non-shielded enemy.


func _init() -> void:
	super._init()
	display_name = "Seeking Missile"
	description = "Tracks the nearest enemy. Slow cadence, heavy damage. Secondary."
	base_damage = 3
	dmg_per_mark = 3
	base_cooldown = 0.75


func _base_ammo() -> int:
	return 60


func _homing() -> bool:
	return true
