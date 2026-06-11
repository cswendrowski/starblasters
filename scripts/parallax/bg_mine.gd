extends Sprite2D

# Decorative background mine for the minefield backdrop (Roman 2026-06-11). Drifts
# DOWN at a parallax-depth speed and wraps at the top; carries a dimmed pulse light
# (added by the coordinator). Pure decoration — no collision, no gameplay.

const VP := Vector2(480.0, 270.0)
var fall_speed: float = 30.0


func _process(delta: float) -> void:
	position.y += fall_speed * delta
	if position.y > VP.y + 24.0:
		position.y = -24.0
		position.x = randf_range(-16.0, VP.x + 16.0)
