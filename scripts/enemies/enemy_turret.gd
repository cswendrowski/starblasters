extends Node2D
class_name EnemyTurret

const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")

# Reusable aiming + firing component. Add as a child of any enemy node.
# Handles player tracking, arc clamping, post-shot rotation lock, and
# bullet spawning. The parent only needs to expose find_player() or be
# in the scene tree so the group scan fallback works.

@export var rotation_speed: float = 2.0          # rad/s
@export var arc_deg: float = 0.0                  # 0 = unlimited; ±arc_deg/2 around rest_angle_deg
@export var rest_angle_deg: float = 0.0           # arc centre in local parent space (deg)
# Arc GATING (Roman 2026-06-08, extracted from the bomber tail gunner): when true and
# arc_deg > 0, the turret HOLDS FIRE while the player is outside the arc (a rear/flank
# gunner with a true blind spot), instead of the default behavior which clamps the aim to
# the arc edge and keeps shooting. The barrel still rotates/clamps toward the player.
@export var arc_gate: bool = false
@export var lock_to_fire: bool = false            # freeze rotation for lock_duration after each shot
@export var lock_duration: float = 0.4            # seconds rotation is locked after firing
@export var fire_interval_min: float = 2.0
@export var fire_interval_max: float = 2.0
@export var aim_tolerance_deg: float = 11.0
# Target leading (spec "aimed_lead", Roman 2026-06-08): 0 = aim at the player's
# CURRENT position ("aimed_wild"); >0 leads by player.velocity × lead_factor
# seconds, so a moving player gets shot ahead of. ~0.2 reads as a competent gunner.
@export var lead_factor: float = 0.0
@export var bullet_variant: BulletVariant = null
@export var bullet_speed: float = 160.0
@export var enabled: bool = true
# Projectile-movement axis (M6a.2): the turret is a firing emitter, so it drives
# homing/wobble on its bullets the same way shoot_pattern does — independent of the
# bullet .tres. >0 overrides the variant's seed.
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0
# Barrel-recoil animation (Roman 2026-06-07): when the turret's barrel Sprite2D is
# a multi-frame strip (frame 0 idle, 1..N-1 recoil), flick through the recoil frames
# on each shot then snap back to idle. 0 = no recoil (single-frame barrels unaffected).
@export var recoil_frames: int = 0

var _barrel: Sprite2D = null
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
	# Barrel = first child Sprite2D (the visual the builder added). Used for recoil.
	for c in get_children():
		if c is Sprite2D:
			_barrel = c
			break


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
		var dir: Vector2 = (_aim_point(player) - global_position).normalized()
		target_rot = atan2(dir.y, dir.x) + PI * 0.5
		if arc_deg > 0.0:
			var center: float = p.global_rotation + deg_to_rad(rest_angle_deg)
			target_rot = _clamp_to_arc(target_rot, center, deg_to_rad(arc_deg * 0.5))
	var diff := angle_difference(_turret_rot, target_rot)
	_turret_rot += clamp(diff, -rotation_speed * delta, rotation_speed * delta)
	# _turret_rot is a WORLD-space aim angle (atan2 to the player). `rotation` is
	# LOCAL to the parent, so subtract the parent's world rotation to keep the
	# turret's GLOBAL facing on target even when the hull is auto-rotated to face
	# its travel direction (Roman 2026-06-08). On an unrotated hull global_rotation
	# is 0, so this is a no-op for fixed-facing platforms (gunship, cruiser, etc.).
	rotation = _turret_rot - p.global_rotation
	_fire_t += delta
	_try_fire()


func _try_fire() -> void:
	if _fire_t < _next_interval:
		return
	var player := find_player()
	if player == null:
		return
	var dir: Vector2 = (_aim_point(player) - global_position).normalized()
	var target_rot: float = atan2(dir.y, dir.x) + PI * 0.5
	# Arc gate: a blind-spot gunner holds fire when the player is outside its cone (the
	# RAW aim, before the _process arc-clamp). The barrel may sit at the arc edge; no shot.
	if arc_gate and arc_deg > 0.0:
		var p := get_parent()
		if p != null:
			var center: float = p.global_rotation + deg_to_rad(rest_angle_deg)
			if abs(angle_difference(center, target_rot)) > deg_to_rad(arc_deg * 0.5):
				return
	if abs(angle_difference(_turret_rot, target_rot)) > deg_to_rad(aim_tolerance_deg):
		# Not aimed yet — do NOT reset _fire_t; check again next frame.
		return
	_fire_t = 0.0
	_next_interval = randf_range(fire_interval_min, fire_interval_max)
	_shoot()
	if recoil_frames > 0:
		_recoil()
	if lock_to_fire:
		_locked = true
		_lock_t = lock_duration


func _shoot() -> void:
	var fire_dir := Vector2(cos(_turret_rot - PI * 0.5), sin(_turret_rot - PI * 0.5))
	var EnemyBullet = load("res://scenes/projectiles/enemy_bullet.tscn")
	if EnemyBullet == null:
		return
	# Fire from the parent enemy's muzzle marker when it has one (gun_turret
	# has a `Muzzle`), else from this turret node's own position. Mount-only
	# enemies (firecore_cruiser's turret_mount, bulwark) report has_muzzles()
	# == false and are unchanged. A pink flash plays at the muzzle on a hit.
	var p := get_parent()
	var has_mz: bool = p != null and p.has_method("has_muzzles") and p.has_muzzles()
	var spawn_pos: Vector2 = global_position
	if has_mz:
		spawn_pos = p.next_muzzle_pos()
	var b = EnemyBullet.instantiate()
	if bullet_variant != null and "variant" in b:
		b.variant = bullet_variant
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(spawn_pos, fire_dir)
	else:
		b.global_position = spawn_pos
		if "velocity_dir" in b:
			b.velocity_dir = fire_dir
		if "speed" in b:
			b.speed = bullet_speed
		elif "velocity" in b:
			b.velocity = fire_dir * bullet_speed
	# Movement axis — drive homing/wobble post-spawn (after _apply_variant seeded),
	# so the firing layer (turret) owns movement, not the bullet .tres.
	if homing_rate > 0.0 and "homing_rate" in b:
		b.homing_rate = homing_rate
	if wobble_amplitude > 0.0 and "wobble_amplitude" in b:
		b.wobble_amplitude = wobble_amplitude
		b.wobble_frequency = wobble_frequency
	if has_mz:
		var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
		MuzzleFx.play_enemy(spawn_pos, fire_dir, get_tree().root)
	# Fire sound — classified off this turret's own bullet_variant (small/tracer
	# → enemy_mg, else enemy_blaster). Positional at the muzzle.
	EnemySfxC.play(get_tree().root, spawn_pos, EnemySfxC.kind_for(self))


# Flick the barrel through its recoil frames (1 -> max -> back to idle 0) on a shot.
func _recoil() -> void:
	if _barrel == null or not is_instance_valid(_barrel) or _barrel.hframes < 2:
		return
	var last: int = mini(recoil_frames, _barrel.hframes - 1)
	_barrel.frame = 1
	var tw := create_tween()
	tw.tween_interval(0.04)
	tw.tween_callback(func(): if is_instance_valid(_barrel): _barrel.frame = last)
	tw.tween_interval(0.07)
	tw.tween_callback(func(): if is_instance_valid(_barrel): _barrel.frame = 0)


# World point to aim at: the player's current position, optionally led by
# velocity × lead_factor (spec aimed_wild vs aimed_lead). Falls back to the raw
# position when the player has no `velocity` to predict from.
func _aim_point(player: Node) -> Vector2:
	var p: Vector2 = player.global_position
	if lead_factor > 0.0 and "velocity" in player:
		p += player.velocity * lead_factor
	return p


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
