extends Area2D
class_name ShieldDrone

# Ablative shield drone. Orbits the player at a fixed radius, blocks
# bullets + collisions, takes a small number of hits before being
# destroyed. Cobalt 2026-05-21: Drone Bits secondary now spawns 3 of
# these instead of piggybacking primary fire.

# Tunable via the Drone Bits part:
@export var orbit_radius: float = 18.0
@export var orbit_speed: float = 2.4   # radians/sec
@export var max_hits: int = 2

var _player: Node2D = null
var _angle: float = 0.0
var _hits: int = 0
var _dying: bool = false


func _ready() -> void:
	# Bullets/enemies enter the drone's area; we intercept the entry and
	# eat one hit per contact.
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func bind_player(player: Node2D, start_angle: float, hp: int) -> void:
	_player = player
	_angle = start_angle
	max_hits = max(1, hp)
	_hits = 0


func _process(delta: float) -> void:
	if _dying:
		return
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_angle += orbit_speed * delta
	position = _player.global_position + Vector2(cos(_angle), sin(_angle)) * orbit_radius


# Bullet / collision contact — the drone absorbs one hit then dies on
# the max_hits-th contact. Only enemy projectiles (groups: "enemies",
# "enemy_bullets", "bullets") count as hits; player bullets carry no
# group and are filtered out by the whitelist below.
func _on_area_entered(area: Area2D) -> void:
	if _dying:
		return
	# Only intercept enemy bullets / enemies, not the player, own drones, or
	# player bullets. Player bullets carry no group so we whitelist hostile
	# groups instead of blacklisting friendly ones.
	if area == _player:
		return
	if area.is_in_group("shield_drones") or area.is_in_group("player_drones") or area.is_in_group("player"):
		return
	if not (area.is_in_group("enemies") or area.is_in_group("enemy_bullets") or area.is_in_group("bullets")):
		return
	_hits += 1
	if _hits >= max_hits:
		_explode()


# Public — called by ShieldDrone-aware bullets or by drone_bits cleanup.
func take_hit(_damage: int = 1) -> bool:
	if _dying:
		return false
	_hits += 1
	if _hits >= max_hits:
		_explode()
		return true
	return false


func _explode() -> void:
	if _dying:
		return
	_dying = true
	var ExplosionFxCls = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFxCls:
		ExplosionFxCls.play(global_position, 0.5, false)
	queue_free()
