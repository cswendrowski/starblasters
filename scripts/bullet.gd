extends "res://scripts/projectiles/base_bullet.gd"

# Player bullet. Inherits the unified hit pipeline + offscreen kill from
# BaseBullet; this script just sets player-side defaults (heads up,
# damages enemies) and attaches the cyan glow / optional trail.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
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
	# Subtle shader halo, color auto-derived from the bullet sprite (cyan
	# bolts glow cyan, etc.). Replaces the old radial GlowFX + scene "Glow"
	# child. See scripts/effects/glow_shader_fx.gd.
	GlowShaderFx.apply_to_host(self)
	if guided:
		TrailFX.attach_trail(self, true)
