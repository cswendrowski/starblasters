extends EnemyBase
class_name EnemyGunship

# Wave role assigned by the director via on_spawned_in_wave().
# Values: "single" | "duo_a" | "duo_b" | "trio_left" | "trio_center" | "trio_right"
# Defaults to "single" for backward compatibility (manual placement, dev menu, etc.)
@export var wave_role: String = "single"

# If true, the ship hull rotates to face the player during combat.
# Bullets always aim at the player regardless; this only affects the visual rotation.
@export var aim_at_player: bool = false

const ROCKET_SCENE = preload("res://scenes/projectiles/enemy_rocket.tscn")
const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

# --- Shared tuning constants -------------------------------------------------
const ENTER_SPEED   := 120.0  # px/s descent into position
const LEAVE_SPEED   := 140.0  # px/s ascent when exiting
const SWEEP_SPEED   := 40.0   # px/s horizontal sweep
const SALVO_SIZE    := 3      # rockets per salvo (override per role below)
const SALVO_COUNT   := 3      # salvos before exiting
const SALVO_INTERVAL := 0.5   # seconds between salvos

# --- Gun burst constants (same rhythm as old turret) -------------------------
const BURST_SIZE     := 10    # bullets per burst
const BURST_DELAY    := 0.1   # seconds between bullets within a burst
const BURST_COOLDOWN := 2.0   # seconds between bursts
const TRACER_BULLET_SPEED := 300.0  # px/s; matches Strafer's speed for visual consistency

# --- State machine -----------------------------------------------------------
enum GState { ENTERING, ACTIVE, EXITING }
var _state: int = GState.ENTERING

# Settle Y by role — duo B sits slightly lower to stagger visuals
var _settle_y: float = 60.0
var _target_x: float = 0.0   # for sweep / stationary X targets
var _sweep_dir: int = 1      # +1 right, -1 left

var _salvo_timer: float = 0.0
var _salvos_fired: int = 0
var _next_rocket_idx: int = 0  # cycles 0..5 across launch_point markers

# --- Gun burst state --------------------------------------------------------
var _burst_shots_fired: int = 0
var _burst_timer: float = 0.0        # delay between shots within burst
var _burst_cooldown_timer: float = 0.0  # delay between bursts; counts down while > 0
var _in_burst: bool = false
var _next_muzzle_left: bool = true   # alternates gun muzzles: L / R / L / R

# --- Ship aim state (for aim_at_player) -----------------------------------
var _ship_rotation: float = 0.0  # current rotation toward player


func _ready() -> void:
	max_health    = 12
	bounty_value  = 30
	auto_rotate   = false
	display_scale = 1.0
	super._ready()
	# Default single starting X: centre of playfield
	global_position.x = Playfield.CENTER.x
	_target_x = Playfield.X_MIN + 20.0  # first sweep target (leftward)
	_ship_rotation = 0.0


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
			_update_ship_aim(delta)  # smooth rotation toward player if enabled
		GState.EXITING:
			_do_exit(delta)
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
	# Spawn rocket from one of the 6 launch_pointN markers, cycling through them.
	if ROCKET_SCENE == null:
		return
	var marker := get_node_or_null("launch_point%d" % (_next_rocket_idx + 1)) as Marker2D
	if marker == null:
		return
	_next_rocket_idx = (_next_rocket_idx + 1) % 6

	var r = ROCKET_SCENE.instantiate()
	get_tree().root.add_child(r)
	# Rockets fire in the direction the hull is facing with ±15° random deviation.
	# Forward vector: at rotation 0, faces down (0,1); rotates with the hull.
	var forward := Vector2.DOWN.rotated(_ship_rotation)
	var fire_dir := forward.rotated(randf_range(-deg_to_rad(15.0), deg_to_rad(15.0)))
	var spawn_pos := marker.global_position
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


# --- Gun burst firing -------------------------------------------------------

func _do_burst_fire(delta: float) -> void:
	if _in_burst:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_gun_bullet()
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


func _fire_gun_bullet() -> void:
	# Fire tracer bullets from alternating muzzles, aiming at the player.
	if BULLET_SCENE == null:
		return

	# Pick the next muzzle marker (MuzzleL or MuzzleR), alternating each shot.
	var muzzle_name: String = "MuzzleL" if _next_muzzle_left else "MuzzleR"
	_next_muzzle_left = !_next_muzzle_left
	var muzzle := get_node_or_null(muzzle_name) as Marker2D
	var spawn_pos: Vector2 = muzzle.global_position if muzzle else global_position

	var b = BULLET_SCENE.instantiate()
	get_tree().root.add_child(b)

	# Aim at player's current position (no leading).
	var player = find_player()
	var fire_dir := Vector2(0, 1)  # default straight down
	if player != null:
		fire_dir = (player.global_position - spawn_pos).normalized()

	if b.has_method("start"):
		b.start(spawn_pos, fire_dir)
	elif "velocity" in b:
		b.velocity = fire_dir * TRACER_BULLET_SPEED

	# Muzzle flash at the firing location
	if muzzle:
		MuzzleFx.play_enemy(spawn_pos, fire_dir, get_tree().root)


func _update_ship_aim(delta: float) -> void:
	# Smoothly rotate the ship hull to face the player (if aim_at_player is enabled).
	# The sprite points up (north), so target rotation is angle-to-player + PI/2.
	if not aim_at_player:
		return

	const ROTATION_SPEED := 2.2  # rad/s; same speed as old turret tracking
	var player = find_player()
	var target_rot: float = 0.0  # default: face straight up (sprite convention)
	if player:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		target_rot = atan2(dir.y, dir.x) + PI * 0.5

	# Smoothly rotate toward target.
	var diff := angle_difference(_ship_rotation, target_rot)
	_ship_rotation += clamp(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)
	self.rotation = _ship_rotation
