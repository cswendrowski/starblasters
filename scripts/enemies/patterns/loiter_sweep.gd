extends "res://scripts/enemies/movement_pattern.gd"

# Loiter Sweep (Roman 2026-06-08, ported from enemy_beam_shooter locomotion; renamed from
# "beam_sweep" 2026-06-09 — behavior unchanged): descend to a settle band, then rake left↔right
# across the playfield at a steady speed. Movement-only — the host keeps its (shared BeamEmitter)
# beam + hull-aim. Persistent (never exits). Emits phase_entered("settled") once it reaches the band.

const Playfield = preload("res://scripts/systems/playfield.gd")

signal phase_entered(phase_name: String)

@export var settle_y: float = 58.0
@export var enter_speed: float = 170.0
@export var sweep_speed: float = 42.0
@export var sweep_margin: float = 22.0   # keep the hull off the gutter edges

enum Ph { ENTER, SWEEP }
var _ph: int = Ph.ENTER
var _dir: int = 1
var _target_x: float = 0.0


func on_start(enemy) -> void:
	_ph = Ph.ENTER
	# Sweep outward from the spawn side so a pair fans apart rather than overlapping.
	_dir = -1 if enemy.position.x < Playfield.CENTER.x else 1
	_target_x = (Playfield.X_MIN + sweep_margin) if _dir < 0 else (Playfield.X_MAX - sweep_margin)


func compute_step(enemy, delta: float) -> Vector2:
	if _ph == Ph.ENTER:
		var sy: float = enter_speed * delta
		if enemy.position.y + sy >= settle_y:
			sy = settle_y - enemy.position.y
			_ph = Ph.SWEEP
			phase_entered.emit("settled")
		return Vector2(0.0, sy)
	# SWEEP — bounce between the margins.
	if absf(_target_x - enemy.position.x) < 2.0:
		_dir = -_dir
		_target_x = (Playfield.X_MIN + sweep_margin) if _dir < 0 else (Playfield.X_MAX - sweep_margin)
	var nx: float = clampf(enemy.position.x + float(_dir) * sweep_speed * delta,
		Playfield.X_MIN + sweep_margin, Playfield.X_MAX - sweep_margin)
	return Vector2(nx - enemy.position.x, 0.0)
