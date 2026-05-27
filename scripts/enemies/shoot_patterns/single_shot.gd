extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires one bullet straight down.

@export var bullet_variant: BulletVariant = null


func fire(enemy) -> void:
	_spawn_bullet(enemy, Vector2(0, 1), bullet_variant)
