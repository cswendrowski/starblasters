extends "res://scripts/projectiles/base_bullet.gd"

# Enemy bullet. Heads down by default, damages the player group. Adopts
# the unified pipeline (BaseBullet handles offscreen kill + damage
# routing); this script just sets enemy-side defaults and visuals.

const GlowFX = preload("res://scripts/effects/glow_fx.gd")
const TrailFX = preload("res://scripts/trail_fx.gd")


func _init() -> void:
	target_group = "player"
	velocity_dir = Vector2(0, 1)
	speed = 200.0


func _apply_visuals() -> void:
	# Warm orange-red glow halo to match the enemy projectile palette.
	GlowFX.attach_glow(self, Color(1.0, 0.55, 0.25), 0.75, 0.6)
	if guided:
		TrailFX.attach_trail(self, false)
