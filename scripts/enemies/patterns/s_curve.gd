extends "res://scripts/enemies/movement_pattern.gd"

# Sin-wave horizontal swing around the spawn x, while descending. Amplitude
# auto-clamps so a spawn near the wall doesn't push the enemy out the side.

# 320×400 res rework: halved.
@export var down_speed: float = 72.0
@export var amplitude: float = 70.0
@export var frequency: float = 1.4
# Mirror flag — flips the lateral swing direction (sin → -sin). Designer
# feedback 2026-05-24: top-down traversing patterns should support mirrored
# variants for visual variety.
@export var mirrored: bool = false

var _t: float = 0.0
var _start_x: float = 0.0


func on_start(enemy) -> void:
	_t = 0.0
	_start_x = enemy.position.x


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	# Bounce against the 216-px playfield band, not the 480-px viewport,
	# so the swing stays where the player can shoot it.
	var max_amp: float = min(_start_x - (Playfield.X_MIN + 22.0), (Playfield.X_MAX - 22.0) - _start_x)
	var safe_amp: float = min(amplitude, max(max_amp, 8.0))
	var sign_x: float = -1.0 if mirrored else 1.0
	var target_x: float = _start_x + sign_x * sin(_t * frequency) * safe_amp
	return Vector2(target_x - enemy.position.x, down_speed * delta)
