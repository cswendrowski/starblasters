extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires one bullet aimed at the player. Falls back to straight down if no
# player is in the tree. Lead factor multiplies player.velocity to lead
# the shot.

@export var lead_factor: float = 0.0
@export var bullet_variant: BulletVariant = null


func fire(enemy) -> void:
	_spawn_bullet(enemy, _aim_at_player(enemy, lead_factor), bullet_variant)
