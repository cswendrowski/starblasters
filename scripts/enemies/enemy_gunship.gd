extends EnemyBase
class_name EnemyGunship

# Wave role assigned by the director via on_spawned_in_wave().
# Values: "single" | "duo_a" | "duo_b" | "trio_left" | "trio_center" | "trio_right"
# Defaults to "single" for backward compatibility (manual placement, dev menu, etc.)
@export var wave_role: String = "single"

const ROCKET_SCENE = preload("res://scenes/projectiles/enemy_rocket.tscn")
const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")

# --- Shared tuning constants -------------------------------------------------
const ENTER_SPEED   := 120.0  # px/s descent into position
const LEAVE_SPEED   := 140.0  # px/s ascent when exiting
const SWEEP_SPEED   := 40.0   # px/s horizontal sweep
const SALVO_SIZE    := 3      # rockets per salvo (override per role below)
const SALVO_COUNT   := 3      # salvos before exiting
const SALVO_INTERVAL := 0.5   # seconds between salvos

# --- Turret burst constants --------------------------------------------------
const BURST_SIZE     := 10    # bullets per burst
const BURST_DELAY    := 0.1   # seconds between bullets within a burst
const BURST_COOLDOWN := 2.0   # seconds between bursts

# --- State machine -----------------------------------------------------------
enum GState { ENTERING, ACTIVE, EXITING }
var _state: int = GState.ENTERING

# Settle Y by role — duo B sits slightly lower to stagger visuals
var _settle_y: float = 60.0
var _target_x: float = 0.0   # for sweep / stationary X targets
var _sweep_dir: int = 1      # +1 right, -1 left

var _salvo_timer: float = 0.0
var _salvos_fired: int = 0
var _rocket_side: int = -1  # alternates -1 (left) / +1 (right) per rocket

# --- Turret burst state -----------------------------------------------------
var _burst_shots_fired: int = 0
var _burst_timer: float = 0.0        # delay between shots within burst
var _burst_cooldown_timer: float = 0.0  # delay between bursts; counts down while > 0
var _in_burst: bool = false


func _ready() -> void:
	max_health    = 12
	bounty_value  = 30
	auto_rotate   = false
	display_scale = 1.0
	super._ready()
	# Default single starting X: centre of playfield
	global_position.x = Playfield.CENTER.x
	_target_x = Playfield.X_MIN + 20.0  # first sweep target (leftward)
	# Turret starts facing straight down (same direction as main sprite)
	var turret := get_node_or_null("Turret") as Sprite2D
	if turret != null:
		turret.rotation = 0.0


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
	# Stagger offset applied when transitioning to ACTIVE so rockets don't
	# fire all at once in formations. Stored here; applied in _do_enter().
	match wave_role:
		"trio_left":   _salvo_timer = SALVO_INTERVAL + 0.15
		"trio_right":  _salvo_timer = SALVO_INTERVAL + 0.30
		"duo_b":       _salvo_timer = SALVO_INTERVAL + 0.20
		_:             _salvo_timer = SALVO_INTERVAL


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
		# _salvo_timer was set to SALVO_INTERVAL (+ stagger) in _apply_role_config.
		# It is NOT decremented during ENTERING, so the ship fully settles before
		# firing its first salvo. Burst cooldown mirrors the salvo stagger.
		_burst_cooldown_timer = _salvo_timer


func _do_active(delta: float) -> void:
	_salvo_timer -= delta
	if _salvo_timer <= 0.0:
		_fire_salvo()
		_salvos_fired += 1
		if _salvos_fired >= SALVO_COUNT:
			_state = GState.EXITING
			return
		_salvo_timer = SALVO_INTERVAL

	_do_burst_fire(delta)

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
	for i in count:
		_fire_rocket()


func _fire_rocket() -> void:
	if ROCKET_SCENE == null:
		return
	var r = ROCKET_SCENE.instantiate()
	get_tree().root.add_child(r)
	# Rockets fire straight down with ±15° random deviation.
	var fire_dir := Vector2(0, 1).rotated(randf_range(-deg_to_rad(15.0), deg_to_rad(15.0)))
	# Alternate spawn offsets: left (-8) then right (+8) per rocket
	var offset_x: float = _rocket_side * 8.0
	_rocket_side = -_rocket_side
	var spawn_pos := global_position + Vector2(offset_x, 0.0)
	if r.has_method("start"):
		r.start(spawn_pos, fire_dir)
	elif "velocity" in r:
		r.velocity = fire_dir * 280.0
	# Render rocket behind the gunship sprite
	r.z_as_relative = false
	r.z_index = z_index - 1

	# Rocket launch SFX
	var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfx:
		WeaponSfx.play(get_tree().root, global_position, "rocket")


# --- Turret burst firing -----------------------------------------------------

func _do_burst_fire(delta: float) -> void:
	if _in_burst:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_turret_bullet()
			_burst_shots_fired += 1
			if _burst_shots_fired >= BURST_SIZE:
				# Burst complete — enter cooldown
				_in_burst = false
				_burst_cooldown_timer = BURST_COOLDOWN
			else:
				_burst_timer = BURST_DELAY
	else:
		_burst_cooldown_timer -= delta
		if _burst_cooldown_timer <= 0.0:
			# Start a new burst
			_in_burst = true
			_burst_shots_fired = 0
			_burst_timer = 0.0  # fire first bullet immediately


func _fire_turret_bullet() -> void:
	if BULLET_SCENE == null:
		return
	var b = BULLET_SCENE.instantiate()
	get_tree().root.add_child(b)
	# Aim at player's current position (no leading)
	var player = find_player()
	var fire_dir := Vector2(0, 1)  # default straight down
	if player != null:
		fire_dir = (player.global_position - global_position).normalized()
	if b.has_method("start"):
		b.start(global_position, fire_dir)
	elif "velocity" in b:
		b.velocity = fire_dir * 200.0


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
