extends "res://scripts/enemy_core.gd"

# Weaver variant of enemy_core: bullet-based shoot_pattern is disabled;
# instead fires two rockets (±6 px on X) when crossing Y ≈ 135 (midpoint of
# the 0–270 playfield). Rockets travel straight down at default speed.
#
# Spawning: as children of get_tree().root so they survive the weaver's death.

const EnemyRocket = preload("res://scenes/projectiles/enemy_rocket.tscn")

const ROCKET_TRIGGER_Y: float = 135.0
const ROCKET_OFFSET_X: float = 6.0

var _rockets_fired: bool = false


func _ready() -> void:
	super._ready()
	# Disable the bullet-based shoot pattern; the Weaver attacks via rockets only.
	shoot_pattern = null
	if has_node("ShootTimer"):
		$ShootTimer.stop()


func _process(delta: float) -> void:
	super._process(delta)
	if _rockets_fired or _dying or _cycling:
		return
	if global_position.y >= ROCKET_TRIGGER_Y:
		_fire_rockets()


func _fire_rockets() -> void:
	_rockets_fired = true
	var down: Vector2 = Vector2(0, 1)
	for offset_x in [-ROCKET_OFFSET_X, ROCKET_OFFSET_X]:
		var rocket = EnemyRocket.instantiate()
		get_tree().root.add_child(rocket)
		rocket.scale = Vector2(1.5, 1.5)
		rocket.start(global_position + Vector2(offset_x, 0), down)
