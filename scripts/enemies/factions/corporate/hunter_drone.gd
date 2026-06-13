extends "res://scripts/enemy_core.gd"

# Hunter Drone. Flashes red, beelines for the player (beeline_player
# movement), explodes on contact dealing hull damage. Doesn't shoot; the
# whole point is the kamikaze. No bounty for the easy kill if it hits you
# — destroying it before contact is the only way to claim it.

@export var contact_damage: int = 2

var _pulse_t: float = 0.0


func _ready() -> void:
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	super._ready()
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1.6, 0.5, 0.45, 1.0)
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
	# Destroy the drone if it flies outside the playfield band. The normal
	# kamikaze path keeps it within X 132–348; this catches the edge case
	# where it overshoots or misses the player and would otherwise return
	# from off-screen. _leave() is used (not explode) — no bounty, no died
	# signal, no camera trauma for a clean miss.
	if global_position.x < 132.0 or global_position.x > 348.0 \
			or global_position.y < -50.0 or global_position.y > 290.0:
		_leave()
		return
	# Red-pulse blink — drives a brightness sine on the sprite.
	if has_node("Sprite2D"):
		_pulse_t += delta * 6.0
		var k: float = 1.2 + 0.5 * sin(_pulse_t)
		$Sprite2D.modulate = Color(k * 1.3, 0.45, 0.40, 1.0)


# Self-destruct on player contact. Also handled in enemy_core.gd's standard
# area_entered → player damage path, but we want to ensure the drone always
# detonates (not just damages) on touch.
func _on_contact(area: Area2D) -> void:
	if area == self:
		return
	if area.has_method("take_damage") and "hull" in area:
		# Kamikaze rule: only a shoot-down BEFORE contact pays out. Reaching the
		# player drops the bounty — zeroed here AND in take_hit() below, because
		# the player's ram (take_hit(6)) may win the overlap race against this
		# self-destruct and would otherwise award the bounty itself.
		bounty_value = 0
		area.take_damage(contact_damage)
		explode()


# The player rams overlapping enemies for take_hit(6) (player._on_area_entered),
# which one-shots this 2-HP drone. If that ram is the killing blow it's still a
# contact kill, so drop the bounty to match _on_contact — reaching the player
# never pays out. A normal bullet hit (player far below) leaves the bounty intact.
func take_hit(damage: int = 1) -> bool:
	for a in get_overlapping_areas():
		if a.has_method("take_damage") and "hull" in a:
			bounty_value = 0
			break
	return super.take_hit(damage)
