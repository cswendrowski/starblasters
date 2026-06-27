extends "res://scripts/enemies/movement_pattern.gd"

# Lateral drift for self-propelled-looking HAZARDS (asteroids/mines/firecores — bodies that don't
# canonically move under their own power). One movement pattern, four modes, confining the sideways
# wander to a different lateral envelope (Roman 2026-06-23):
#   STRAIGHT  — no drift; descends straight in its spawn lane (the existing straight behavior).
#   LANE      — slow weave WITHIN its own lane (±half a lane width).
#   ADJACENT  — weave into the two neighbouring lanes, but no further (±one lane pitch).
#   ALL       — free drift across the whole playfield band, reflecting off the edges (the old
#               asteroid default — fixed initial velocity, lightly damped on each bounce).
#
# Reusable two ways: an enemy_core hazard (mine) consumes it through its movement slot; a bespoke
# _process hazard (asteroid/firecore) instantiates one and applies the lateral component itself
# (keeping its own descent + collision response). compute_step returns the full (lateral, descent)
# step so the slot path also gets vertical motion. Preload-referenced, no class_name (matches the
# other pattern Resources).

const Lanes = preload("res://scripts/systems/lanes.gd")

enum Mode { STRAIGHT, LANE, ADJACENT, ALL }

@export var mode: int = Mode.ALL
# Descent speed for the SLOT path (enemy_core). 0 → fall back to the chassis _move_speed. Bespoke
# hazards ignore the returned dy and keep their own descent, so they leave this at 0.
@export var down_speed: float = 0.0
@export var lateral_speed: float = 10.0   # px/s sideways wander (matches the old asteroid ±10)
@export var edge_margin: float = 6.0      # band inset for ALL mode (matches the old asteroid clamp)

# Per-instance state (reset in on_start; captured lazily on the first step once position is set).
# NB: NOT named `_init` — that shadows the GDScript constructor and breaks .new().
var _started: bool = false
var _lo: float = 0.0
var _hi: float = 0.0
var _vx: float = 0.0


# Map an authored/conductor movement key to a mode. Unknown → ALL (the asteroid default), so an
# unconfigured hazard keeps drifting freely.
static func mode_from_key(key: String) -> int:
	match key:
		"straight": return Mode.STRAIGHT
		"drift_lane": return Mode.LANE
		"drift_adjacent": return Mode.ADJACENT
		"drift_all": return Mode.ALL
		_: return Mode.ALL


func on_start(_enemy) -> void:
	_started = false   # re-capture home + reseed velocity on (re)start


func compute_step(enemy, delta: float) -> Vector2:
	if not _started:
		_setup(enemy)
	var dy: float = (down_speed if down_speed > 0.0 else _move_speed(enemy)) * delta
	if mode == Mode.STRAIGHT or _hi <= _lo:
		return Vector2(0.0, dy)
	var x: float = enemy.position.x
	var nx: float = x + _vx * delta
	if nx <= _lo:
		nx = _lo
		_vx = _bounce_speed()          # now travelling right (+)
	elif nx >= _hi:
		nx = _hi
		_vx = -_bounce_speed()         # now travelling left (-)
	return Vector2(nx - x, dy)


# Lateral velocity to bias the hazard back toward its envelope (e.g. a collision shove). Clamped to
# the wander magnitude so a kick can't fling it out of its lane. Used by asteroid collision response.
func nudge_lateral(vx: float) -> void:
	_vx = clampf(vx, -lateral_speed * 2.0, lateral_speed * 2.0)


# Current lateral velocity (px/s). The asteroid reads it for the death-burst debris cone direction.
func current_vx() -> float:
	return _vx


func _setup(enemy) -> void:
	_started = true
	var home: float = enemy.position.x
	match mode:
		Mode.STRAIGHT:
			_lo = home
			_hi = home
			_vx = 0.0
			return
		Mode.LANE:
			var half: float = Lanes.WIDTH * 0.5
			_lo = home - half
			_hi = home + half
		Mode.ADJACENT:
			_lo = home - Lanes.PITCH
			_hi = home + Lanes.PITCH
		_:   # ALL
			_lo = Playfield.X_MIN + edge_margin
			_hi = Playfield.X_MAX - edge_margin
	# Never let the envelope spill outside the playable band.
	_lo = maxf(_lo, Playfield.X_MIN + edge_margin)
	_hi = minf(_hi, Playfield.X_MAX - edge_margin)
	_vx = (-1.0 if randf() < 0.5 else 1.0) * lateral_speed


# Speed magnitude after a bounce. ALL lightly damps (slows toward vertical — the old asteroid feel);
# the confined weaves keep their pace (re-randomized a touch so they don't ping-pong mechanically).
func _bounce_speed() -> float:
	if mode == Mode.ALL:
		return absf(_vx) * 0.6
	return lateral_speed * randf_range(0.7, 1.0)
