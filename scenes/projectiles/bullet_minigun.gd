extends "res://scripts/projectiles/base_bullet.gd"

# Minigun / tracer bullet. Fast, small, light damage. Shares the unified
# bullet pipeline so it goes through take_hit + bulwark-shielded check
# instead of the legacy `area.health -=` path it used to.


func _init() -> void:
	target_group = "enemies"
	velocity_dir = Vector2(0, -1)
	# 240 px/s pairs with the minigun's 0.0333s cadence → 8px shot pitch, a 4px
	# gap between the 4px-tall bullets (Roman 2026-06-11 projectile conversion).
	speed = 240.0
	# Warm yellow tracer — matches the gun_tracer strip.
	impact_color = Color(1.0, 0.92, 0.5, 1.0)
	impact_kind = 0  # SMOKE


# minigun_tracer is a 2-frame strip. ALTERNATE the frame each shot (Roman
# 2026-06-11) so the stream reads as distinct ticking rounds, not a static line.
static var _frame_toggle: int = 0

func _ready() -> void:
	if has_node("Sprite2D"):
		var s: Sprite2D = $Sprite2D
		if s.hframes > 1:
			s.frame = _frame_toggle
			_frame_toggle = (_frame_toggle + 1) % s.hframes
	super._ready()
