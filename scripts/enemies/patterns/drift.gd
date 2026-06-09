extends "res://scripts/enemies/movement_pattern.gd"

# Drift (Roman 2026-06-08, reworked from bulwark_drift): slowly descend to a hold height, then a
# jiggled drift in place within the lane (a tank / holder). drift_low/mid/high pick the height
# (same bands as the loiter patterns). Persistent hold — it doesn't exit on its own.
#
# Per-instance RANDOMIZED (Roman 2026-06-08): each enemy seeds its own phase offset + a small
# jiggle-speed variation in on_start, so a row of drifters wanders out of sync instead of
# lock-stepping (the pattern Resource is duplicated per enemy, so on_start runs per instance).

const Playfield = preload("res://scripts/playfield.gd")

@export var hover_y: float = 90.0
@export var enter_speed: float = 60.0
@export var jiggle_px: float = 6.0
# Jiggle speed matched to the Loiter holder's bob (Roman 2026-06-09: drift was
# jiggling far too fast). Loiter uses freq_y 0.6 Hz / freq_x 0.35 Hz; with drift's
# Y term running at _spd * 1.3, _spd 0.45 lands Y ~= 0.585 Hz and X ~= 0.45 Hz, in
# the loiter band. Both formulas are sin(t * speed * TAU), so the units line up.
@export var jiggle_speed: float = 0.45

var _held: bool = false
var _hold: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _phase: float = 0.0     # per-instance phase offset (radians)
var _spd: float = 0.45      # per-instance jiggle speed (jiggle_speed * random factor)


func on_start(_enemy) -> void:
	_held = false
	_t = 0.0
	_phase = randf() * TAU
	_spd = jiggle_speed * randf_range(0.82, 1.18)   # desync frequency too, so they drift apart


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	if not _held:
		var sy: float = enter_speed * delta
		if enemy.position.y + sy >= hover_y:
			sy = hover_y - enemy.position.y
			_held = true
			_hold = Vector2(enemy.position.x, hover_y)
		return Vector2(0.0, sy)
	# Jiggled drift around the hold point (two desynced sines per axis = organic wander), each
	# offset by the per-instance phase so neighbouring drifters don't move identically.
	var tx: float = _hold.x + sin(_t * _spd * TAU + _phase) * jiggle_px \
		+ sin(_t * _spd * 0.6 + _phase) * jiggle_px * 0.4
	var ty: float = _hold.y + cos(_t * _spd * 1.3 * TAU + _phase * 1.7) * jiggle_px * 0.5
	tx = clampf(tx, Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
	return Vector2(tx - enemy.position.x, ty - enemy.position.y)
