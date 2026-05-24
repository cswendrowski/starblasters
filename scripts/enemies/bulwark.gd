extends "res://scripts/enemies/enemy_base.gd"

# Bulwark v2 (Roman 2026-05-18 redesign). Slow, chunky, shielded enemy
# that holds the center of the screen as a barrier. Uncommon-tough class
# with 2× the normal shield charges and self-regenerating shield (like
# the player). Inertial-thrust movement aimed at the screen center, not
# the player. Weak weapon — it's a tank, not a damage dealer.
#
# Sprite: tiny_ship11 at 1× scale (set in scene). Shield ring matches
# the player's shield visual so the player understands "this thing eats
# bullets the same way I do."

const BulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const TurretTex = preload("res://graphics/enemies/tank_turret.png")

# --- Stats --------------------------------------------------------------
@export var shield_charges_max: int = 4        # 2× uncommon-tough baseline
@export var shield_recharge_interval: float = 6.0
@export var fire_interval_min: float = 2.3
@export var fire_interval_max: float = 3.2
@export var bullet_speed: float = 180.0

# --- Movement (inertial drift toward screen center) ---------------------
@export var move_speed_max: float = 60.0
@export var accel: float = 90.0
@export var center_target: Vector2 = Vector2(240, 90)
@export var arrive_radius: float = 12.0

var _vel: Vector2 = Vector2.ZERO
var _shield: int = 0
var _recharge_t: float = 0.0
var _fire_t: float = 0.0

# Turret (created in _ready, rotates to track player).
@export var turret_offset: Vector2 = Vector2(0, -4)  # local offset from base center
@export var turret_track_rate: float = 4.0           # lerp_angle rate
@export var turret_barrel_length: float = 9.0        # spawn bullet this far along barrel
var _turret: Sprite2D = null

const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")

signal hull_changed(max_hull, hull)


func _ready() -> void:
	if max_health <= 1:
		max_health = 8        # uncommon-tough HP
	if bounty_value <= 0:
		bounty_value = 75
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_shield = shield_charges_max
	_fire_t = randf_range(fire_interval_min, fire_interval_max)
	_build_shield_ring()
	_update_shield_visual()
	_build_turret()
	hull_changed.emit(max_health, health)


func _build_turret() -> void:
	_turret = Sprite2D.new()
	_turret.name = "Turret"
	_turret.texture = TurretTex
	_turret.position = turret_offset
	# Render above the base sprite but below the shield ring (z=1).
	_turret.z_index = 0
	_turret.z_as_relative = false
	add_child(_turret)


# Hull shim — engine_torch / damage_smoke_trail look for these.
var hull: int:
	get:
		return health
	set(value):
		health = value
var max_hull: int:
	get:
		return max_health
	set(value):
		max_health = value


func _build_shield_ring() -> void:
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.0)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)
	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1)
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sprite is 36×26 at 1× scale — ring at 48×48 wraps it with breathing room.
	var sz: float = 48.0
	_shield_ring.size = Vector2(sz, sz)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)


func _update_shield_visual() -> void:
	if _shield_mat == null:
		return
	var lit: float = 0.0
	if _shield > 0:
		lit = clamp(float(_shield) / float(max(1, shield_charges_max)), 0.25, 1.0)
	_shield_mat.set_shader_parameter("alpha", lit * 0.85)


# Shield absorbs first, then hull. Player-style charge system.
func take_hit(damage: int = 1) -> bool:
	if _dying:
		return false
	if _shield > 0:
		_shield -= 1
		if _shield_mat:
			_shield_mat.set_shader_parameter("hit_strength", 1.0)
			if _shield_hit_tween and _shield_hit_tween.is_valid():
				_shield_hit_tween.kill()
			_shield_hit_tween = create_tween()
			_shield_hit_tween.tween_method(func(v): _shield_mat.set_shader_parameter("hit_strength", v), 1.0, 0.0, 0.4)
		_update_shield_visual()
		if has_node("Sprite2D"):
			HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_SHIELD)
		hull_changed.emit(max_health, health)
		# Reset recharge timer so taking hits delays regeneration.
		_recharge_t = 0.0
		return false
	var was_killed: bool = super.take_hit(damage)
	hull_changed.emit(max_health, health)
	return was_killed


func _process(delta: float) -> void:
	if _dying:
		return
	# Inertial thrust toward the center. Decelerates as it nears the
	# target so it settles without overshoot — chunky and deliberate.
	var to_target: Vector2 = center_target - position
	var dist: float = to_target.length()
	var desired_vel: Vector2 = Vector2.ZERO
	if dist > arrive_radius:
		desired_vel = to_target.normalized() * move_speed_max
	_vel = _vel.move_toward(desired_vel, accel * delta)
	position += _vel * delta
	# Shield regeneration. Tick the timer once a hit has cooled; add one
	# charge per interval up to max.
	if _shield < shield_charges_max:
		_recharge_t += delta
		if _recharge_t >= shield_recharge_interval:
			_recharge_t = 0.0
			_shield = mini(_shield + 1, shield_charges_max)
			_update_shield_visual()
	# Turret tracks player smoothly (visual only — bullet aim is direct).
	_update_turret_rotation(delta)
	# Weapon. Slow, aimed shot at the player.
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = randf_range(fire_interval_min, fire_interval_max)
		_fire_at_player()


func _update_turret_rotation(delta: float) -> void:
	if _turret == null:
		return
	var player := find_player()
	if player == null:
		return
	# Sprite faces up by convention — same +PI/2 as _apply_auto_rotation.
	var target: float = (player.global_position - _turret.global_position).angle() + PI / 2.0
	_turret.rotation = lerp_angle(_turret.rotation, target, turret_track_rate * delta)


func _fire_at_player() -> void:
	var player := find_player()
	if player == null:
		return
	# Spawn position: along the turret's current "up" direction (barrel tip).
	# Sprite-up = -Y rotated by turret rotation; convention puts angle 0 at -Y.
	var muzzle: Vector2 = global_position
	if _turret != null:
		var up_dir: Vector2 = Vector2.UP.rotated(_turret.rotation)
		muzzle = _turret.global_position + up_dir * turret_barrel_length
	var b = BulletScene.instantiate()
	b.global_position = muzzle
	# Bullet aims straight at the player from the muzzle position — clean,
	# avoids the bullet "missing" while the turret is mid-lerp.
	var to_p: Vector2 = (player.global_position - muzzle).normalized()
	if "velocity_dir" in b:
		b.velocity_dir = to_p
	if "speed" in b:
		b.speed = bullet_speed
	get_tree().root.add_child(b)
