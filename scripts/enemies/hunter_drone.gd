extends "res://scripts/enemy_core.gd"

# Hunter Drone. Flashes red, beelines for the player (beeline_player
# movement), explodes on contact dealing hull damage. Doesn't shoot; the
# whole point is the kamikaze. No bounty for the easy kill if it hits you
# — destroying it before contact is the only way to claim it.

@export var contact_damage: int = 2

var _pulse_t: float = 0.0
var _pulse_glow: Sprite2D = null


func _ready() -> void:
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	super._ready()
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1.6, 0.5, 0.45, 1.0)
		# Attach an additive red halo behind the sprite so the pulse reads
		# as a glow, not just a brightness flicker (Roman, 2026-05-17:
		# "add a shader that makes the red portion pulse/glow"). Lives at
		# the same scope as the sprite so it tracks the drone position.
		var GlowFx = load("res://scripts/effects/glow_fx.gd")
		if GlowFx:
			_pulse_glow = GlowFx.attach_glow($Sprite2D, Color(1.0, 0.15, 0.10), 1.6, 0.7)
	area_entered.connect(_on_contact)
	# Hunter drones are kamikazes — they don't shoot, no matter what shoot
	# pattern the wave director assigned (Roman, 2026-05-16). Clear the
	# slot + stop the timer so enemy_core's _on_shoot_timer_timeout never
	# fires.
	shoot_pattern = null
	if has_node("ShootTimer"):
		$ShootTimer.stop()


func _process(delta: float) -> void:
	super._process(delta)
	# Red-pulse blink — drives a brightness sine on the sprite AND on the
	# additive halo so the red portion reads as glowing, not just blinking.
	if has_node("Sprite2D"):
		_pulse_t += delta * 6.0
		var k: float = 1.2 + 0.5 * sin(_pulse_t)
		$Sprite2D.modulate = Color(k * 1.3, 0.45, 0.40, 1.0)
		if _pulse_glow != null and is_instance_valid(_pulse_glow):
			var ga: float = 0.55 + 0.35 * sin(_pulse_t)
			_pulse_glow.modulate.a = ga
			var gs: float = 1.5 + 0.25 * sin(_pulse_t)
			_pulse_glow.scale = Vector2(gs, gs)


# Self-destruct on player contact. Also handled in enemy_core.gd's standard
# area_entered → player damage path, but we want to ensure the drone always
# detonates (not just damages) on touch.
func _on_contact(area: Area2D) -> void:
	if area == self:
		return
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(contact_damage)
		explode()
