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
	# When a BulletVariant is active its glow_color already drove the scene's
	# "Glow" child (or will be applied via GlowFX below), so skip the default
	# orange-red halo to avoid overpainting the variant color.
	if variant == null:
		GlowFX.attach_glow(self, Color(1.0, 0.55, 0.25), 0.75, 0.6)
	else:
		# Attach a programmatic glow using the variant's color, since
		# enemy_bullet.tscn's Glow node was already colored in _apply_variant.
		GlowFX.attach_glow(self, variant.glow_color, 0.75, 0.6)
	if guided:
		TrailFX.attach_trail(self, false)
