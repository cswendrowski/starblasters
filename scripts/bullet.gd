extends "res://scripts/projectiles/base_bullet.gd"

# Player bullet. Inherits the unified hit pipeline + offscreen kill from
# BaseBullet; this script just sets player-side defaults (heads up,
# damages enemies) and attaches the cyan glow / optional trail.

const GlowFX = preload("res://scripts/effects/glow_fx.gd")
const TrailFX = preload("res://scripts/trail_fx.gd")


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
	# Cyan glow halo — sized just slightly larger than the bullet sprite so
	# it reads as a charged shot without painting the screen.
	GlowFX.attach_glow(self, Color(0.55, 0.9, 1.0), 0.75, 0.6)
	if guided:
		TrailFX.attach_trail(self, true)
