extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires one bullet straight down.

func fire(enemy) -> void:
	_spawn_bullet(enemy, Vector2(0, 1))
