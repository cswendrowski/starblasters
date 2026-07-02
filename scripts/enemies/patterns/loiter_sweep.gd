extends "res://scripts/enemies/movement_pattern.gd"

# Loiter Sweep (Roman 2026-06-08, ported from enemy_beam_shooter locomotion; renamed from
# "beam_sweep" 2026-06-09 — behavior unchanged): descend to a settle band, then rake left↔right
# across the playfield at a steady speed. Movement-only — the host keeps its (shared BeamEmitter)
# beam + hull-aim. Persistent (never exits). Emits phase_entered("settled") once it reaches the band.

const Playfield = preload("res://scripts/systems/playfield.gd")

signal phase_entered(phase_name: String)

@export var settle_y: float = 58.0
@export var sweep_margin: float = 22.0   # keep the hull off the gutter edges
# Locomotion refactor 2026-06-19: descent speed is chassis-owned; the lateral rake is a fraction
# of it (preserves the old 170→42 feel). settle_y is resolved from the enemy/formation DEPTH. The
# enter_speed/sweep_speed exports above are vestigial.
const SWEEP_RATIO: float = 42.0 / 170.0

enum Ph { ENTER, SWEEP }
var _ph: int = Ph.ENTER
var _dir: int = 1
var _target_x: float = 0.0


func on_start(enemy) -> void:
	_ph = Ph.ENTER
	# Settle DEPTH is chassis/formation-owned now (locomotion refactor); fall back to settle_y.
	settle_y = Zones.y_for_progress(_depth_bp(enemy, Zones.band_progress(settle_y)))
	# Sweep outward from the spawn side so a pair fans apart rather than overlapping.
	_dir = -1 if enemy.position.x < Playfield.CENTER.x else 1
	_target_x = (Playfield.X_MIN + sweep_margin) if _dir < 0 else (Playfield.X_MAX - sweep_margin)


func compute_step(enemy, delta: float) -> Vector2:
	if _ph == Ph.ENTER:
		# Descent speed is chassis-owned now (locomotion refactor); `enter_speed` is vestigial.
		# Shared descend-to-depth snap (review §7 dedup) — arrival flips _ph + emits the settle phase.
		var arrived: Array = [false]
		var sy: float = descend_to(enemy, settle_y, _move_speed(enemy), delta, arrived)
		if arrived[0]:
			_ph = Ph.SWEEP
			phase_entered.emit("settled")
		return Vector2(0.0, sy)
	# SWEEP — bounce between the margins.
	if absf(_target_x - enemy.position.x) < 2.0:
		_dir = -_dir
		_target_x = (Playfield.X_MIN + sweep_margin) if _dir < 0 else (Playfield.X_MAX - sweep_margin)
	var nx: float = clampf(enemy.position.x + float(_dir) * _move_speed(enemy) * SWEEP_RATIO * delta,
		Playfield.X_MIN + sweep_margin, Playfield.X_MAX - sweep_margin)
	return Vector2(nx - enemy.position.x, 0.0)


# Opt into unit-weighted inertia (ship kinematics §7 increment 2 — 2026-07-02) so the margin
# reversal + the descend→sweep settle pivot ease through their velocity snaps instead of flipping
# instantly. The smoothing lives in enemy_core; the settle trigger is the position-Y clamp above,
# which lags a frame or two under inertia but still resolves correctly.
func uses_inertia() -> bool:
	return true
