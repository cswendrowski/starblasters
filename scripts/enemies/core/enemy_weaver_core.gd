extends "res://scripts/enemy_core.gd"

# Weaver variant of enemy_core: bullet-based shoot_pattern is disabled;
# instead fires two rockets (±6 px on X) when crossing Y ≈ 135 (midpoint of
# the 0–270 playfield). Rockets travel straight down at default speed.
#
# Spawning: as children of get_tree().root so they survive the weaver's death.

const EnemyRocket = preload("res://scenes/projectiles/enemy_rocket.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

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
	# One rocket per muzzle (MuzzleL then MuzzleR — name-sorted by the base),
	# each spawning at the live marker position with a pink flash. Falls back
	# to the ±6 px offsets if the markers are ever removed.
	var spawns: Array = all_muzzle_pos() if has_muzzles() else [
		global_position + Vector2(-ROCKET_OFFSET_X, 0),
		global_position + Vector2(ROCKET_OFFSET_X, 0),
	]
	var flashing: bool = has_muzzles()
	for spawn_pos in spawns:
		var rocket = EnemyRocket.instantiate()
		get_tree().root.add_child(rocket)
		rocket.scale = Vector2(1.5, 1.5)
		rocket.start(spawn_pos, down)
		if flashing:
			MuzzleFx.play_enemy(spawn_pos, down, get_tree().root)
	# One launch whoosh per volley from the universal rocket pool.
	WeaponSfx.play(get_tree().root, global_position, "rocket")
