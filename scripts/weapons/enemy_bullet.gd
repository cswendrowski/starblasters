extends "res://scripts/projectiles/base_bullet.gd"

# Enemy bullet. Heads down by default, damages the player group. Adopts
# the unified pipeline (BaseBullet handles offscreen kill + damage
# routing); this script just sets enemy-side defaults and visuals.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const TrailFX = preload("res://scripts/trail_fx.gd")


func _init() -> void:
	target_group = "player"
	velocity_dir = Vector2(0, 1)
	speed = 60.0


func _apply_visuals() -> void:
	# Subtle shader halo, color AUTO-DERIVED from the bullet sprite (brightest
	# non-white pixel) — no per-weapon authoring. BulletVariant.glow_color is
	# now vestigial for glow purposes (see scripts/projectiles/bullet_variant.gd).
	GlowShaderFx.apply_to_host(self)
	if guided:
		TrailFX.attach_trail(self, false)
