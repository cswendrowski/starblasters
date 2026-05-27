extends "res://scripts/enemy_core.gd"

# Weaver variant of enemy_core: fires one aimed rocket mid-path (1.5–2.5 s
# after spawn) in addition to its normal spread-shot pattern. The rocket aims
# at the player's current position at the moment of firing.
#
# Spawning: as a child of get_tree().root so it survives the weaver's death.
# Scale: 1.5× the base rocket sprite for visual distinctiveness.

const EnemyRocket = preload("res://scenes/projectiles/enemy_rocket.tscn")

var _rocket_fired: bool = false
var _rocket_timer: float = 0.0
var _rocket_delay: float = 0.0


func _ready() -> void:
	super._ready()
	_rocket_delay = randf_range(1.5, 2.5)


func _process(delta: float) -> void:
	super._process(delta)
	if _rocket_fired or _dying or _cycling:
		return
	_rocket_timer += delta
	if _rocket_timer >= _rocket_delay:
		_fire_rocket()


func _fire_rocket() -> void:
	_rocket_fired = true
	var player := find_player()
	var dir: Vector2 = Vector2(0, 1)
	if player != null:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length_squared() > 0.01:
			dir = to_p.normalized()

	var rocket = EnemyRocket.instantiate()
	get_tree().root.add_child(rocket)
	rocket.scale = Vector2(1.5, 1.5)
	if rocket.has_method("start"):
		rocket.start(global_position, dir)
	else:
		rocket.global_position = global_position
