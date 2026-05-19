extends "res://scripts/projectiles/base_bullet.gd"

# Minigun / tracer bullet. Fast, small, light damage. Shares the unified
# bullet pipeline so it goes through take_hit + bulwark-shielded check
# instead of the legacy `area.health -=` path it used to.

func _init() -> void:
	target_group = "enemies"
	velocity_dir = Vector2(0, -1)
	# Bumped 175 -> 600 per Roman 2026-05-17 playtest: "MG bullets need to
	# be much faster". Tracer aesthetic supports the higher speed.
	speed = 600.0
	# Warm yellow tracer — matches the tracer-yellow.png sprite.
	impact_color = Color(1.0, 0.92, 0.5, 1.0)
	impact_kind = 0  # SMOKE
