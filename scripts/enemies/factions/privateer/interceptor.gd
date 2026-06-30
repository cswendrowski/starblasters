extends "res://scripts/enemies/enemy_core.gd"

# Interceptor / Wing. Dives top→bottom quickly, dropping homing missiles on the way through. The
# missile-drop USED to live here as bespoke logic; it was generalized into an EmitterComponent
# (roster "emitters": a band-gated, drops-per-pass TIMER emit of drifting_missile.tscn) on 2026-06-17,
# so any enemy can carry it and the Enemy Bench can tune it.
#
# This script carries the no-recycle exit (interceptors leave the bottom and STAY GONE) plus an
# OPT-IN bombing run: when bombing_run_enabled, the wing transitions out mid-dive and carpet-bombs a
# lane pattern (seq_bombing_run), then exits. Default OFF so ordinary dive waves are unchanged.

const BombingRunAttack = preload("res://scripts/enemies/bombing_run_attack.gd")

@export var bombing_run_enabled: bool = false
var _bomb_done: bool = false
var _bomb_seq: Node = null


func _process(delta: float) -> void:
	if external_control:
		return                        # bombing-run sequence owns the transform
	super._process(delta)
	if not _dying:
		_tick_bombing_run()


func _tick_bombing_run() -> void:
	if not bombing_run_enabled or _bomb_done or _bomb_seq != null:
		return
	# Fire once the wing has dived into the engagement band.
	if Zones.band_progress(global_position.y) < 0.35:
		return
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return
	_bomb_done = true
	external_control = true
	_bomb_seq = BombingRunAttack.launch(self, spr, {
		"pattern": float(randi() % 4),
		"direction": 0.0,             # top→bottom, matching the wing's dive
		"return_mode": 1.0,           # exit after the run — wings don't loiter
	})
	if _bomb_seq == null:
		external_control = false
		return
	_bomb_seq.finished.connect(_on_bomb_done)


func _on_bomb_done() -> void:
	_bomb_seq = null
	if is_instance_valid(self):
		queue_free()                  # spent its run; leaves


# Interceptors dive to the bottom and STAY GONE — they never recycle. enemy_core._on_offscreen
# hands off to RecycleController.recycle(); override it back to a clean leave so the wing exits for
# good regardless of any wave-assigned recycle_passes. (Was a bespoke _start_cycle override before
# RecycleController owned the fly-back, 2026-06-29.)
func _on_offscreen() -> void:
	_leave()
