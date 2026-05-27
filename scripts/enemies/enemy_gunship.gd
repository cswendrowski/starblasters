extends EnemyBase
class_name EnemyGunship

# Wave role assigned by the director via on_spawned_in_wave().
# Values: "single" | "duo_a" | "duo_b" | "trio_left" | "trio_center" | "trio_right"
# Defaults to "single" for backward compatibility (manual placement, dev menu, etc.)
@export var wave_role: String = "single"

const ROCKET_SCENE = preload("res://scenes/projectiles/enemy_rocket.tscn")

# --- Shared tuning constants -------------------------------------------------
const ENTER_SPEED   := 120.0  # px/s descent into position
const LEAVE_SPEED   := 140.0  # px/s ascent when exiting
const SWEEP_SPEED   := 40.0   # px/s horizontal sweep
const SALVO_SIZE    := 3      # rockets per salvo (override per role below)
const SALVO_COUNT   := 3      # salvos before exiting
const SALVO_INTERVAL := 1.5   # seconds between salvos

# --- State machine -----------------------------------------------------------
enum GState { ENTERING, ACTIVE, EXITING }
var _state: int = GState.ENTERING

# Settle Y by role — duo B sits slightly lower to stagger visuals
var _settle_y: float = 60.0
var _target_x: float = 0.0   # for sweep / stationary X targets
var _sweep_dir: int = 1      # +1 right, -1 left

var _salvo_timer: float = 0.0
var _salvos_fired: int = 0


func _ready() -> void:
	max_health    = 12
	bounty_value  = 30
	auto_rotate   = false
	display_scale = 1.0
	super._ready()
	# Default single starting X: centre of playfield
	global_position.x = Playfield.CENTER.x
	_target_x = Playfield.X_MIN + 20.0  # first sweep target (leftward)


# Called by the director immediately after spawning this enemy.
# index = 0-based spawn order within the wave; count = total in wave.
func on_spawned_in_wave(index: int, count: int) -> void:
	match count:
		1:
			wave_role = "single"
		2:
			wave_role = "duo_a" if index == 0 else "duo_b"
		_:
			# 3 or more: left / center / right; extras wrap as right
			match index:
				0: wave_role = "trio_left"
				1: wave_role = "trio_center"
				2: wave_role = "trio_right"
				_: wave_role = "trio_right"
	_apply_role_config()


func _apply_role_config() -> void:
	match wave_role:
		"single":
			_settle_y = 60.0
			_sweep_dir = 1 if randf() < 0.5 else -1
			_target_x = Playfield.X_MIN + 20.0 if _sweep_dir > 0 else Playfield.X_MAX - 20.0
		"duo_a":
			_settle_y = 50.0
			_sweep_dir = 1   # sweeps right
			_target_x = Playfield.X_MIN + 20.0
		"duo_b":
			_settle_y = 70.0
			_sweep_dir = -1  # sweeps left (pass through duo_a)
			_target_x = Playfield.X_MAX - 20.0
		"trio_left":
			_settle_y = 60.0
			_target_x = Playfield.X_MIN + 20.0
		"trio_center":
			_settle_y = 60.0
			_target_x = Playfield.CENTER.x
		"trio_right":
			_settle_y = 60.0
			_target_x = Playfield.X_MAX - 20.0
		_:
			# Unknown role — treat as single so there are no silent fallbacks
			wave_role = "single"
			_settle_y = 60.0
			_sweep_dir = 1
			_target_x = Playfield.X_MIN + 20.0
	# Seed the salvo timer so all three don't fire simultaneously on the same tick
	# Trio center fires first; left/right staggered slightly
	match wave_role:
		"trio_left":   _salvo_timer = 0.15
		"trio_right":  _salvo_timer = 0.30
		"duo_b":       _salvo_timer = 0.20
		_:             _salvo_timer = 0.0


func _process(delta: float) -> void:
	if _dying:
		return
	match _state:
		GState.ENTERING:
			_do_enter(delta)
		GState.ACTIVE:
			_do_active(delta)
		GState.EXITING:
			_do_exit(delta)
	_track_player(delta)
	super._process(delta)


func _do_enter(delta: float) -> void:
	global_position.y += ENTER_SPEED * delta
	# For fixed-position roles (trio/duo), glide x toward target during entry
	# so the formation slots into place cleanly regardless of director spawn x.
	if wave_role in ["trio_left", "trio_center", "trio_right", "duo_a", "duo_b"]:
		global_position.x = move_toward(global_position.x, _target_x, ENTER_SPEED * 2.0 * delta)
	if global_position.y >= _settle_y:
		global_position.y = _settle_y
		_state = GState.ACTIVE
		# _salvo_timer was pre-seeded by _apply_role_config; no reassignment needed


func _do_active(delta: float) -> void:
	_salvo_timer -= delta
	if _salvo_timer <= 0.0:
		_fire_salvo()
		_salvos_fired += 1
		if _salvos_fired >= SALVO_COUNT:
			_state = GState.EXITING
			return
		_salvo_timer = SALVO_INTERVAL

	match wave_role:
		"single", "duo_a", "duo_b":
			_do_sweep(delta)
		"trio_left", "trio_center", "trio_right":
			_do_oscillate(delta)


func _do_sweep(delta: float) -> void:
	# Sweep toward _target_x; on arrival reverse direction
	var dx: float = _target_x - global_position.x
	if abs(dx) < 2.0:
		# Reached target — flip direction
		_sweep_dir = -_sweep_dir
		_target_x = Playfield.X_MIN + 20.0 if _sweep_dir > 0 else Playfield.X_MAX - 20.0
	global_position.x += _sweep_dir * SWEEP_SPEED * delta
	global_position.x = clamp(global_position.x, Playfield.X_MIN + 10.0, Playfield.X_MAX - 10.0)


func _do_oscillate(delta: float) -> void:
	# Gentle sinusoidal wobble around _target_x (±8 px, 0.6 Hz)
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var wobble: float = sin(t * TAU * 0.6) * 8.0
	global_position.x = _target_x + wobble
	global_position.y = _settle_y  # hold altitude


func _do_exit(delta: float) -> void:
	global_position.y -= LEAVE_SPEED * delta
	if global_position.y < -80.0:
		queue_free()


func _fire_salvo() -> void:
	var count: int = SALVO_SIZE
	# Single and duo get 4-rocket salvos for a bit more density
	if wave_role in ["single", "duo_a", "duo_b"]:
		count = 4
	var spread_total: float = deg_to_rad(20.0)
	for i in count:
		var t: float = float(i) / float(max(count - 1, 1))
		var angle_offset: float = lerp(-spread_total * 0.5, spread_total * 0.5, t)
		_fire_rocket(angle_offset)


func _fire_rocket(extra_angle: float = 0.0) -> void:
	if ROCKET_SCENE == null:
		return
	var r = ROCKET_SCENE.instantiate()
	get_tree().root.add_child(r)
	# Aim turret at player, then fire in that direction + jitter
	var turret := get_node_or_null("Turret") as Sprite2D
	var fire_rot: float = turret.rotation if turret != null else (PI * 0.5)  # default: straight down
	var fire_dir := Vector2(cos(fire_rot - PI * 0.5), sin(fire_rot - PI * 0.5))
	fire_dir = fire_dir.rotated(extra_angle)
	if r.has_method("start"):
		r.start(global_position, fire_dir)
	elif "velocity" in r:
		r.velocity = fire_dir * 280.0

	# Rocket launch SFX
	var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfx:
		WeaponSfx.play(get_tree().root, global_position, "rocket")


func _track_player(delta: float) -> void:
	var player = find_player()
	const ROTATION_SPEED := 2.2  # rad/s
	var target_rot: float = PI * 0.5  # default: aim straight down
	if player:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		target_rot = atan2(dir.y, dir.x) + PI * 0.5
	var turret := get_node_or_null("Turret") as Sprite2D
	if turret == null:
		return
	var diff := angle_difference(turret.rotation, target_rot)
	turret.rotation += clamp(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)
