extends "res://scripts/enemies/enemy_core.gd"

# Interceptor. Dives top→bottom of the screen quickly (top_dive pattern),
# dropping homing missiles on the way through. The missiles drift briefly
# then ignite and chase the player. Missiles can be shot down.
#
# Interceptors don't recycle — they exit the bottom and stay gone.

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const MissileScene = preload("res://scenes/projectiles/drifting_missile.tscn")

@export var drop_interval: float = 0.55
@export var drops_per_pass: int = 3

var _drop_t: float = 0.0
var _drops_left: int = 0


func _ready() -> void:
	super._ready()
	_drops_left = drops_per_pass


func _process(delta: float) -> void:
	super._process(delta)
	if _cycling or _drops_left <= 0:
		return
	# Don't drop while still entering from above the playfield, or after
	# leaving the bottom.
	var sy: float = screensize.y
	if global_position.y < 60.0 or global_position.y > sy - 80.0:
		return
	_drop_t -= delta
	if _drop_t <= 0.0:
		_drop_t = drop_interval
		_drop_missile()
		_drops_left -= 1


func _drop_missile() -> void:
	var m = MissileScene.instantiate()
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	world.add_child(m)
	if m.has_method("start"):
		m.start(global_position)
	else:
		m.global_position = global_position
	# Universal missile launch sound (shared with the player's seeking missiles).
	WeaponSfx.play(get_tree().root, global_position, "missile")


# Override the cycle hook from enemy_core so interceptors stay gone after
# they leave the bottom — don't fly back up through the parallax.
func _start_cycle() -> void:
	# Mark the enemy as cycling so the rest of _process skips it, then
	# defer-free instead of running the parallax fly-back.
	_cycling = true
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	queue_free()
