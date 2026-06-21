extends "res://scripts/projectiles/base_bullet.gd"

# Minigun / tracer bullet. Fast, small, light damage. Shares the unified
# bullet pipeline so it goes through take_hit + bulwark-shielded check
# instead of the legacy `area.health -=` path it used to.

const GlowFx = preload("res://scripts/effects/glow_fx.gd")


func _init() -> void:
	target_group = "enemies"
	velocity_dir = Vector2(0, -1)
	# Bumped 175 -> 600 per Roman 2026-05-17 playtest: "MG bullets need to
	# be much faster". Tracer aesthetic supports the higher speed.
	speed = 360.0
	# Warm yellow tracer — matches the gun_tracer strip.
	impact_color = Color(1.0, 0.92, 0.5, 1.0)
	impact_kind = 0  # SMOKE


# Cobalt 2026-05-21: gun_tracer.png is a 3-frame strip. Pick a random
# frame per shot so consecutive tracers don't visually repeat.
func _ready() -> void:
	if has_node("Sprite2D"):
		var s: Sprite2D = $Sprite2D
		if s.hframes > 1:
			s.frame = randi() % s.hframes
	super._ready()


func _apply_visuals() -> void:
	# Subtle warm-amber radial halo behind the tracer. The blurry per-sprite
	# glow_halo shader was retired (Roman 2026-06-20); glow_fx is the clean
	# radial replacement and impact_color matches the tracer strip.
	if has_node("Sprite2D"):
		GlowFx.attach_glow($Sprite2D, impact_color, 0.6, 0.6)
