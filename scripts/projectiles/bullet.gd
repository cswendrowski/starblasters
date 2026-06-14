extends "res://scripts/projectiles/base_bullet.gd"

# Player bullet. Inherits the unified hit pipeline + offscreen kill from
# BaseBullet; this script just sets player-side defaults (heads up,
# damages enemies) and attaches the cyan glow / optional trail.

const TrailFX = preload("res://scripts/effects/trail_fx.gd")


func _init() -> void:
	target_group = "enemies"
	velocity_dir = Vector2(0, -1)
	# 320×400 res rework: bullets halve speed so they cross the same
	# fraction of the playfield per second.
	speed = 700.0
	# Cyan/blue energy bolt — impact flash matches.
	impact_color = Color(0.55, 0.9, 1.0, 1.0)
	impact_kind = 0  # SMOKE


func _apply_visuals() -> void:
	# No per-bullet glow halo — the WorldEnvironment bloom glows the bright bolt sprite directly
	# (Roman 2026-06-12, glow-halo redundancy pass). Only the optional guided trail remains.
	if guided:
		TrailFX.attach_trail(self, true)
