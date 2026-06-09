extends "res://scripts/enemies/movement_pattern.gd"

# Drift (Roman 2026-06-08, reworked from bulwark_drift): slowly descend to a hold height, then a
# jiggled drift in place within the lane (a tank / holder). drift_low/mid/high pick the height
# (same bands as the loiter patterns). Persistent hold — it doesn't exit on its own.

const Playfield = preload("res://scripts/playfield.gd")

@export var hover_y: float = 90.0
@export var enter_speed: float = 60.0
@export var jiggle_px: float = 6.0
@export var jiggle_speed: float = 1.4

var _held: bool = false
var _hold: Vector2 = Vector2.ZERO
var _t: float = 0.0


func on_start(_enemy) -> void:
	_held = false
	_t = 0.0


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	if not _held:
		var sy: float = enter_speed * delta
		if enemy.position.y + sy >= hover_y:
			sy = hover_y - enemy.position.y
			_held = true
			_hold = Vector2(enemy.position.x, hover_y)
		return Vector2(0.0, sy)
	# Jiggled drift around the hold point (two desynced sines per axis = organic wander).
	var tx: float = _hold.x + sin(_t * jiggle_speed * TAU) * jiggle_px \
		+ sin(_t * jiggle_speed * 0.6) * jiggle_px * 0.4
	var ty: float = _hold.y + cos(_t * jiggle_speed * 1.3 * TAU) * jiggle_px * 0.5
	tx = clampf(tx, Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
	return Vector2(tx - enemy.position.x, ty - enemy.position.y)
