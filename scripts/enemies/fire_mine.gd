extends "res://scripts/enemies/enemy_base.gd"

# Fire mine — stationary spinning hazard dropped by the Burner enemy.
# Deals contact damage to the player every DAMAGE_INTERVAL seconds.
# Expires after LIFETIME seconds and can be shot down.

const DAMAGE_INTERVAL := 0.35   # seconds between damage ticks
const LIFETIME        := 5.0    # seconds before the mine fades

var _dmg_t: float = 0.0
var _lifetime_t: float = 0.0
var _spin_speed: float = 4.0    # radians per second
const CONTACT_RADIUS := 14.0    # pixel radius for player-overlap check


func _ready() -> void:
	max_health = 3
	bounty_value = 0
	is_hazard = true
	auto_rotate = false
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	super._ready()
	# Tint orange-red so it reads as fire.
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1.0, 0.5, 0.1, 1.0)


func _process(delta: float) -> void:
	if _dying:
		return
	# Spin in place.
	rotation += _spin_speed * delta
	# Lifetime expiry.
	_lifetime_t += delta
	if _lifetime_t >= LIFETIME:
		_leave()
		return
	# Damage tick — distance-based so we don't need area_entered.
	_dmg_t += delta
	if _dmg_t >= DAMAGE_INTERVAL:
		_dmg_t = 0.0
		var player = find_player()
		if player and global_position.distance_to(player.global_position) <= CONTACT_RADIUS:
			player.take_damage(1)
	super._process(delta)
