extends EnemyBase
class_name EnemyGunTurret

# Gun turret — child of EnemyCruiser. Tracks the player and fires at them
# every FIRE_INTERVAL seconds with a random initial offset so paired
# turrets don't always volley together.

const FIRE_INTERVAL    := 2.5
const BULLET_SPEED     := 160.0
const ROTATION_SPEED   := 1.8   # radians/second (~103 deg/s)
const AIM_TOLERANCE    := 0.18  # radians (~10 deg) — must be aimed within this to fire

var _fire_t: float = 0.0
var _target_rot: float = 0.0


func _ready() -> void:
	max_health   = 4
	bounty_value = 5
	auto_rotate  = false
	display_scale = 0.5
	super._ready()
	_fire_t = randf_range(0.0, FIRE_INTERVAL)


func _process(delta: float) -> void:
	if _dying:
		return
	var player := find_player()
	if player:
		var dir := (player.global_position - global_position).normalized()
		_target_rot = atan2(dir.y, dir.x) + PI * 0.5
	# Rotate toward target at capped speed.
	var diff := angle_difference(rotation, _target_rot)
	rotation += clamp(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)
	_fire_t += delta
	# Only fire when the barrel is actually pointed at the player.
	if _fire_t >= FIRE_INTERVAL and abs(angle_difference(rotation, _target_rot)) < AIM_TOLERANCE:
		_fire_t = 0.0
		_shoot()
	super._process(delta)


func _shoot() -> void:
	# Fire along the barrel's actual current facing, not recomputed toward player,
	# so aim and shot direction always match.
	var fire_dir := Vector2(cos(rotation - PI * 0.5), sin(rotation - PI * 0.5))
	var EnemyBullet = load("res://scenes/projectiles/enemy_bullet.tscn")
	if EnemyBullet == null:
		return
	var b = EnemyBullet.instantiate()
	get_tree().root.add_child(b)
	b.global_position = global_position
	if b.has_method("start"):
		b.start(global_position, fire_dir)
	elif "velocity" in b:
		b.velocity = fire_dir * BULLET_SPEED
