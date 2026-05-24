extends EnemyBase
class_name EnemyGunship

const ROCKET_SCENE     = preload("res://scenes/projectiles/enemy_rocket.tscn")

const SETTLE_Y         := 52.0
const ENTER_SPEED      := 90.0
const ROTATION_SPEED   := 2.2   # rad/s
const BURST_COUNT      := 7
const BURST_INTERVAL   := 0.18  # seconds between rockets
const PRE_BURST_DELAY  := 1.2   # aim before firing
const LEAVE_SPEED      := 120.0

enum GunState { ENTERING, AIMING, BURSTING, LEAVING }
var _state: int = GunState.ENTERING
var _state_t: float = 0.0
var _target_rot: float = 0.0
var _burst_fired: int = 0
var _burst_t: float = 0.0


func _ready() -> void:
	max_health    = 12
	bounty_value  = 30
	auto_rotate   = false
	display_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	if _dying:
		return
	match _state:
		GunState.ENTERING:
			global_position.y += ENTER_SPEED * delta
			if global_position.y >= SETTLE_Y:
				global_position.y = SETTLE_Y
				_state = GunState.AIMING
				_state_t = 0.0
		GunState.AIMING:
			_track_player(delta)
			_state_t += delta
			if _state_t >= PRE_BURST_DELAY:
				_state = GunState.BURSTING
				_burst_fired = 0
				_burst_t = 0.0
		GunState.BURSTING:
			_track_player(delta)
			_burst_t += delta
			if _burst_t >= BURST_INTERVAL:
				_burst_t = 0.0
				_fire_rocket()
				_burst_fired += 1
				if _burst_fired >= BURST_COUNT:
					_state = GunState.LEAVING
		GunState.LEAVING:
			global_position.y -= LEAVE_SPEED * delta
			if global_position.y < -80:
				queue_free()
	super._process(delta)


func _track_player(delta: float) -> void:
	var player = find_player()
	if player:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		_target_rot = atan2(dir.y, dir.x) + PI * 0.5
	# Rotate the Turret child only — the base ship body stays upright like
	# Bulwark. If the scene is missing the Turret child, no-op gracefully.
	var turret := get_node_or_null("Turret") as Sprite2D
	if turret == null:
		return
	var diff := angle_difference(turret.rotation, _target_rot)
	turret.rotation += clamp(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)


func _fire_rocket() -> void:
	if ROCKET_SCENE == null:
		return
	var r = ROCKET_SCENE.instantiate()
	get_tree().root.add_child(r)
	var turret := get_node_or_null("Turret") as Sprite2D
	var fire_rot: float = turret.rotation if turret != null else rotation
	var fire_dir := Vector2(cos(fire_rot - PI * 0.5), sin(fire_rot - PI * 0.5))
	if r.has_method("start"):
		r.start(global_position, fire_dir)
	elif "velocity" in r:
		r.velocity = fire_dir * 280.0
