extends "res://scripts/enemies/movement_pattern.gd"

# Skirmish (Roman 2026-06-08, replaces the broken advance_retreat): descend into the fire zone,
# trace a VERTICAL loop for a few cycles, then exit downward. Both shapes (LOOP, FIGURE8) are tall
# + narrow so they orbit inside the enemy's OWN lane (Roman 2026-06-22 — they used to be horizontal
# orbits that bled across neighbor lanes). Pick the shape via `shape`.

const Playfield = preload("res://scripts/systems/playfield.gd")

enum Shape { LOOP, FIGURE8 }

@export var shape: int = Shape.LOOP
@export var hold_y: float = 90.0
@export var radius_lanes: float = 1.0      # VERTICAL loop radius in lane-pitch units (the X swing is lane-confined)
@export var loop_speed: float = 0.8        # loops per second
@export var loops: float = 2.0             # cycles before exiting
# Locomotion refactor 2026-06-19: descent speed is chassis-owned; the exit is a touch faster
# (ratio preserves the old 120→180 feel). hold_y (the loop depth) is resolved from the
# enemy/formation DEPTH. The *_speed exports above are vestigial; loop_speed/radius/loops stay shape.
const EXIT_RATIO: float = 180.0 / 120.0

var _phase: int = 0    # 0 enter, 1 loop, 2 exit
var _t: float = 0.0
var _center: Vector2 = Vector2.ZERO


func on_start(enemy) -> void:
	_phase = 0
	_t = 0.0
	# Loop DEPTH is chassis/formation-owned now; fall back to the pattern's own hold_y.
	hold_y = Zones.y_for_progress(_depth_bp(enemy, Zones.band_progress(hold_y)))


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		0:  # descend to the loop height
			# Descent speed is chassis-owned now (locomotion refactor); `enter_speed` is vestigial.
			var sy: float = _move_speed(enemy) * delta
			if enemy.position.y + sy >= hold_y:
				sy = hold_y - enemy.position.y
				_phase = 1
				_t = 0.0
				_center = Vector2(enemy.position.x, hold_y)
			return Vector2(0.0, sy)
		1:  # trace the loop — VERTICAL (tall on Y, narrow on X) so it stays in its own lane
			_t += delta
			var a: float = _t * loop_speed * TAU
			var y_amp: float = radius_lanes * Lanes.PITCH            # tall vertical radius
			var x_amp: float = minf(y_amp, Lanes.WIDTH * 0.5 - 2.0)  # narrow X, kept inside the lane interior
			var tx: float
			var ty: float
			if shape == Shape.FIGURE8:
				# Standing figure-8: narrow double-frequency crossover on X, full sweep on Y.
				tx = _center.x + sin(a * 2.0) * x_amp
				ty = _center.y + sin(a) * y_amp
			else:  # LOOP — a tall narrow ellipse hung off the entry point (a=0 maps to _center)
				tx = _center.x + sin(a) * x_amp
				ty = _center.y + (cos(a) - 1.0) * y_amp
			tx = clampf(tx, Playfield.X_MIN + 6.0, Playfield.X_MAX - 6.0)
			if _t >= loops / maxf(loop_speed, 0.01):
				_phase = 2
			return Vector2(tx - enemy.position.x, ty - enemy.position.y)
		_:  # exit
			return Vector2(0.0, _move_speed(enemy) * EXIT_RATIO * delta)


# Opt into unit-weighted inertia (ship kinematics §7 increment 2 — 2026-07-02) so the loop→exit
# snap (and the descend→loop entry) ease through their velocity discontinuities instead of jerking.
# The smoothing lives in enemy_core; _center is captured on the position-Y arrival test above, which
# lags a frame or two under inertia but still resolves correctly (arrival is position-based).
func uses_inertia() -> bool:
	return true
