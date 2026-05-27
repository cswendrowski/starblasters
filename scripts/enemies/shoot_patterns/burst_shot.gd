extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires N bullets straight down, spaced burst_interval seconds apart.
# Uses the base class's _spawn_burst helper (not a recursive await chain)
# so a dying enemy doesn't leave dangling timers.

@export var burst_count: int = 3
@export var burst_interval: float = 0.12
@export var bullet_variant: BulletVariant = null


func fire(enemy) -> void:
	_spawn_burst(enemy, Vector2(0, 1), burst_count, burst_interval, bullet_variant)
