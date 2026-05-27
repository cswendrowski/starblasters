extends Node2D
class_name EnemyTurret

# Reusable aiming + firing component. Add as a child of any enemy node.
# Handles player tracking, arc clamping, post-shot rotation lock, and
# bullet spawning. The parent only needs to expose find_player() or be
# in the scene tree so the group scan fallback works.

@export var rotation_speed: float = 2.0          # rad/s
@export var arc_deg: float = 0.0                  # 0 = unlimited; ±arc_deg/2 around rest_angle_deg
@export var rest_angle_deg: float = 0.0           # arc centre in local parent space (deg)
@export var lock_to_fire: bool = false            # freeze rotation for lock_duration after each shot
@export var lock_duration: float = 0.4            # seconds rotation is locked after firing
@export var fire_interval_min: float = 2.0
@export var fire_interval_max: float = 2.0
@export var aim_tolerance_deg: float = 11.0
@export var bullet_variant: BulletVariant = null
@export var bullet_speed: float = 160.0
@export var enabled: bool = true

var _turret_rot: float = 0.0
var _fire_t: float = 0.0
var _next_interval: float = 2.0
var _locked: bool = false
var _lock_t: float = 0.0


func _ready() -> void:
	_fire_t = randf_range(0.5, fire_interval_max)
	_next_interval = randf_range(fire_interval_min, fire_interval_max)
	var p := get_parent()
	if p and not p.tree_exiting.is_connected(queue_free):
		p.tree_exiting.connect(queue_free)


func _process(delta: float) -> void:
	if not enabled:
		return
	var p := get_parent()
	if p == null or not is_instance_valid(p):
		return

	if _locked:
		_lock_t -= delta
		if _lock_t <= 0.0:
			_locked = false
		_fire_t += delta
		_try_fire()
		return

	var player := find_player()
	var target_rot: float = _turret_rot
	if player:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		target_rot = atan2(dir.y, dir.x) + PI * 0.5
		if arc_deg > 0.0:
			var center := p.global_rotation + deg_to_rad(rest_angle_deg)
			target_rot = _clamp_to_arc(target_rot, center, deg_to_rad(arc_deg * 0.5))
	var diff := angle_difference(_turret_rot, target_rot)
	_turret_rot += clamp(diff, -rotation_speed * delta, rotation_speed * delta)
	rotation = _turret_rot
	_fire_t += delta
	_try_fire()


func _try_fire() -> void:
	if _fire_t < _next_interval:
		return
	var player := find_player()
	if player == null:
		return
	var dir: Vector2 = (player.global_position - global_position).normalized()
	var target_rot: float = atan2(dir.y, dir.x) + PI * 0.5
	if abs(angle_difference(_turret_rot, target_rot)) > deg_to_rad(aim_tolerance_deg):
		# Not aimed yet — do NOT reset _fire_t; check again next frame.
		return
	_fire_t = 0.0
	_next_interval = randf_range(fire_interval_min, fire_interval_max)
	_shoot()
	if lock_to_fire:
		_locked = true
		_lock_t = lock_duration


func _shoot() -> void:
	var fire_dir := Vector2(cos(_turret_rot - PI * 0.5), sin(_turret_rot - PI * 0.5))
	var EnemyBullet = load("res://scenes/projectiles/enemy_bullet.tscn")
	if EnemyBullet == null:
		return
	var b = EnemyBullet.instantiate()
	if bullet_variant != null and "variant" in b:
		b.variant = bullet_variant
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(global_position, fire_dir)
	else:
		b.global_position = global_position
		if "velocity_dir" in b:
			b.velocity_dir = fire_dir
		if "speed" in b:
			b.speed = bullet_speed
		elif "velocity" in b:
			b.velocity = fire_dir * bullet_speed


func find_player() -> Node:
	var p := get_parent()
	if p and p.has_method("find_player"):
		return p.find_player()
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null


func _clamp_to_arc(target: float, center: float, half_arc: float) -> float:
	var d := angle_difference(center, target)
	return center + clamp(d, -half_arc, half_arc)
