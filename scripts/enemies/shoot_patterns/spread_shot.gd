extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires N bullets in a horizontal cone centered straight down.

@export var bullet_count: int = 3
@export var spread_degrees: float = 30.0

func fire(enemy) -> void:
	if bullet_count <= 0:
		return
	var spread_rad := deg_to_rad(spread_degrees)
	var step: float = 0.0
	var start: float = 0.0
	if bullet_count > 1:
		step = spread_rad / float(bullet_count - 1)
		start = -spread_rad * 0.5
	for i in range(bullet_count):
		var angle: float = start + step * float(i)
		# 0 angle = straight down (0, 1); rotate by angle
		var dir := Vector2(sin(angle), cos(angle))
		_spawn_bullet(enemy, dir)
