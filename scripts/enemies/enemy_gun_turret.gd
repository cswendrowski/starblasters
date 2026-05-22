extends EnemyBase
class_name EnemyGunTurret

# Gun turret — child of EnemyCruiser. Tracks the player and fires at them
# every FIRE_INTERVAL seconds with a random initial offset so paired
# turrets don't always volley together.

const FIRE_INTERVAL := 2.5
const BULLET_SPEED  := 160.0

var _fire_t: float = 0.0


func _ready() -> void:
	max_health   = 4
	bounty_value = 5
	auto_rotate  = false
	display_scale = 0.5
	super._ready()
	# Random initial offset so left and right turrets rarely fire together.
	_fire_t = randf_range(0.0, FIRE_INTERVAL)


func _process(delta: float) -> void:
	if _dying:
		return
	var player := find_player()
	if player:
		var dir := (player.global_position - global_position).normalized()
		rotation = atan2(dir.y, dir.x) + PI * 0.5
	_fire_t += delta
	if _fire_t >= FIRE_INTERVAL:
		_fire_t = 0.0
		_shoot()
	super._process(delta)


func _shoot() -> void:
	var player := find_player()
	if player == null:
		return
	var dir := (player.global_position - global_position).normalized()
	var EnemyBullet = load("res://scenes/projectiles/enemy_bullet.tscn")
	if EnemyBullet == null:
		return
	var b = EnemyBullet.instantiate()
	get_tree().root.add_child(b)
	b.global_position = global_position
	if b.has_method("start"):
		b.start(global_position, dir)
	elif "velocity" in b:
		b.velocity = dir * BULLET_SPEED
