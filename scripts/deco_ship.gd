extends Sprite2D

# Decorative drifting ship for the sector-map star chart (Roman 2026-06-11). Slow
# constant drift that wraps at its bounds so the chart reads as a living region.
# Purely cosmetic — no input, no collision.

var velocity: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2(0, 0, 480, 270)


func _process(delta: float) -> void:
	position += velocity * delta
	var m: float = 16.0
	if position.x < bounds.position.x - m:
		position.x = bounds.end.x + m
	elif position.x > bounds.end.x + m:
		position.x = bounds.position.x - m
	if position.y < bounds.position.y - m:
		position.y = bounds.end.y + m
	elif position.y > bounds.end.y + m:
		position.y = bounds.position.y - m
