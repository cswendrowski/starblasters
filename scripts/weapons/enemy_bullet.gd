extends "res://scripts/projectiles/base_bullet.gd"

# Enemy bullet. Heads down by default, damages the player group. Adopts
# the unified pipeline (BaseBullet handles offscreen kill + damage
# routing); this script just sets enemy-side defaults and visuals.

const TrailFX = preload("res://scripts/effects/trail_fx.gd")


func _init() -> void:
	target_group = "player"
	velocity_dir = Vector2(0, 1)
	speed = 60.0


func _apply_visuals() -> void:
	# No per-bullet glow halo — the WorldEnvironment bloom glows the bright bullet sprite directly
	# (Roman 2026-06-12, glow-halo redundancy pass). Only the optional guided trail remains.
	if guided:
		TrailFX.attach_trail(self, false)
