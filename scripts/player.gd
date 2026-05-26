extends Area2D

signal shield_changed
signal hull_changed
signal died
# Emitted whenever take_damage() actually applies damage (before shield/hull
# absorption). Lets the HUD react to the magnitude of the hit without having
# to diff old vs new bar values.
signal damaged(amount: int)

# ---- Stats (mutated by equipped Parts) ----
# Base values; Parts add on top. Gives a sane floor even with no parts equipped.
var speed: float = 125.0  # 320×400 res — halved from 250
var cooldown: float = 0.15
var bullet_damage: int = 1
# Spread fire knobs — used by the Spread Cannon Part. Default 1 bullet
# straight forward (legacy behavior). Spread Cannon's apply() sets
# bullet_spread_count > 1 + bullet_spread_degrees > 0.
var bullet_spread_count: int = 1
var bullet_spread_degrees: float = 0.0
# Per-cannon bullet overrides (Roman, 2026-05-24). Cannons that need to
# scale speed/pierce per Mk write these in apply(); fire_primary stamps
# them onto each spawned bullet. -1 sentinel = "use the bullet scene's
# own default" (no override). Mirrors the bullet_spread_* pattern.
var bullet_speed_override: float = -1.0
var bullet_max_hits_override: int = -1
# Auto Laser tandem firing: when true, fire_primary alternates spawning
# the bullet 8px left / right of the player's pixel center each shot.
# _tandem_side toggles 0/1 between shots.
var fire_tandem_alternating: bool = false
var _tandem_side: int = 0
# Use the rotary laser muzzle FX in place of the default energy muzzle.
# Set by cannons (Auto Laser) that want the rotary laser flash without
# being on the ROTARY_LASER ammo/charge path.
var use_rotary_laser_muzzle: bool = false
# Secondary fire pipeline — HARDPOINT_WING Part assigns these on apply()
# (Seeking Missile, Rocket Pod, future Side Pods / Drone Bits). Separate
# from the primary cannon's bullet_scene / cooldown / damage so the two
# fire independently. secondary_t counts up each frame; when it crosses
# secondary_cooldown the next fire_secondary press emits a bullet.
var secondary_bullet_scene: PackedScene = null
var secondary_cooldown: float = 0.5
var secondary_damage: int = 1
var secondary_homing: bool = false  # true for seeking missile
# Side Pods support — when > 1, fire_secondary spawns multiple bullets
# at offsets symmetrically distributed across the player's wingspan.
# Default 1 = single centered bullet (Seeking Missile, Rocket Pod).
var secondary_pod_count: int = 1
var secondary_pod_halfspan: float = 10.0  # px from center to outermost pod
var _secondary_t: float = 0.0
# Secondary ammo (Rocket Pod / Seeking Missile). -1 = unmetered (default
# for Side Pods / Particle Beam / no secondary). >= 0 = counted; 0 =
# empty, silently fails to fire. Seeded by the Part's apply() from
# Run.secondary_ammo so refills survive scene changes.
var secondary_ammo: int = -1
var secondary_ammo_max: int = -1
signal secondary_ammo_changed(value: int, maximum: int)
# Drone Bits (Gradius Options) — orbiting companions that fire alongside
# the primary. drone_bits holds the spawned drone Node2Ds; fire_primary
# spawns an extra bullet from each drone's global_position each shot.
var drone_bits: Array = []
var drone_bits_damage: int = 1
var drone_bits_bullet_scene: PackedScene = null
# Continuous-beam secondary (Particle Beam). When SecondaryMode.BEAM,
# secondary fire ignores the bullet pipeline and instead runs a held-beam
# tick. Set by ParticleBeam.apply(); BULLET = projectile pipeline (rockets,
# missiles, pods). Migrated from String to enum 2026-05-24 to eliminate
# the empty-string silent fallback.
var secondary_mode: int = WS.SecondaryMode.BULLET
# DPS-based beam damage — secondary_beam_dps × delta per frame, applied
# to every enemy in the column. Frame-rate independent; flat per-Mk
# (Mk grows the width, not the damage).
var secondary_beam_dps: float = 30.0
# Beam width — Particle Beam Part sets this; Mk scales it +1 px / Mk.
# Drives the visual width AND the hit-column tolerance so wider beam
# = larger hit area.
var secondary_beam_width: float = 6.0
# Three-layer beam visual:
#   _beam_halo — wide, low-alpha teal — bloom feel.
#   _beam_line — main beam, full-alpha teal.
#   _beam_core — narrow, white — hot core.
var _beam_halo: Line2D = null
var _beam_line: Line2D = null
var _beam_core: Line2D = null
var _beam_active: bool = false
# Beam pre-fire/hold/cool sprite windup (Cobalt 2026-05-21). Plays
# star_flash strip across the lifetime of a shoot2 hold:
#   - WARMUP: frames 0..3 over BEAM_WARMUP_TIME, beam suppressed
#   - HOLD:   stays on frame 4 with subtle scale jitter while firing
#   - COOLDOWN: frames 4..6 over BEAM_COOLDOWN_TIME after release
const WS = preload("res://scripts/weapons/WeaponStyle.gd")
const BEAM_FLASH_TEX = preload("res://graphics/star_flash.png")
const BEAM_FLASH_HFRAMES := 7
const BEAM_WARMUP_TIME := 0.5
const BEAM_COOLDOWN_TIME := 0.3
# Warm-up = 3 frames (0,1,2), HOLD on frame 3, cool-down plays 4..6.
# Cobalt 2026-05-21: hold-frame was 4, dialed back to 3.
const BEAM_HOLD_FRAME := 3
const BEAM_FRAME_TIME_WARMUP := BEAM_WARMUP_TIME / float(BEAM_HOLD_FRAME)
const BEAM_FRAME_TIME_COOLDOWN := BEAM_COOLDOWN_TIME / float(BEAM_FLASH_HFRAMES - BEAM_HOLD_FRAME - 1)
enum BeamFlashState { NONE, WARMUP, HOLD, COOLDOWN }
var _beam_flash: Sprite2D = null
var _beam_flash_state: int = BeamFlashState.NONE
var _beam_flash_frame_t: float = 0.0
# Super weapon slot — DEVICE_BAY_1 Part assigns itself here on apply().
# Charges are consumed on tap (single-use per press); refilled at
# outposts. Initial charges populated when the part is equipped.
var super_part: Resource = null
var super_charges: int = 0
var max_super_charges: int = 3
signal super_charges_changed(value: int, maximum: int)
# Hyper Mode timer — when > 0, fire_primary triggers every frame
# regardless of GunCooldown, and damage is multiplied. Driven by the
# Hyper super weapon's activate(); ticks down in _process.
var _hyper_t: float = 0.0
const HYPER_DAMAGE_MULT := 2.0
# Exported so player.tscn can assign a fallback bullet; parts override at runtime.
@export var bullet_scene: PackedScene
@export var super_scene: PackedScene
@export var heavy_scene: PackedScene
@export var chain_scene: PackedScene

# Pool of hit-flinch SFX rotated each time the player takes a hit. Two
# variants keep the sound from feeling samey under sustained fire.
const HIT_SFX_POOL: Array = [
	preload("res://Sound/SFX_hit&damage3.wav"),
	preload("res://Sound/SFX_hit&damage9.wav"),
]
var _hit_sfx_idx: int = 0

# Shield: HP pool. Full hit absorbed by shield (no overflow to hull).
# Regen: 5s delay after last hit, then 1/sec until full.
# Roman/spec 2026-05-26 rework: charge-based model retired.
var max_shield: int = 10
var shield: int = 10:
	set = set_shield
# Regen delay tracking. True during 5s countdown after a shield hit;
# false once regen ticks begin (or shield is full).
var _shield_in_delay: bool = false
# shield_recharge_seconds kept as field for save-compat references; no longer written.
var shield_recharge_seconds: float = 5.0
# I-frames in seconds after a shield absorbs a hit. Stops chained
# instant-kills (mine + bomblet) from one-shotting the player.
const SHIELD_INVULN_SECONDS: float = 0.6
var _invuln_t: float = 0.0

# Hull: pip-based (3 pips base). Loss is always 1 pip per hit (not damage).
# Hull == 0 → flash pips; next hit fires super-bomb then kills.
# Roman/spec 2026-05-26 rework.
var max_hull: int = 3
var hull: int = 3:
	set = set_hull
# armor_mk DR retired. Field kept for save compat.
var hull_damage_reduction: float = 0.0
# Speed multiplier from upgrades (Thrusters). Applied
# in _process so the live speed = base * speed_multiplier.
var speed_multiplier: float = 1.0
# Focus-mode slowdown — held `focus` action drops the ship to FOCUS_FACTOR
# of normal speed for precision dodging. Cave / Touhou convention; ~2/3.
const FOCUS_FACTOR := 0.55
var _focus_dot: Node2D = null

var can_shoot: bool = true
var is_alive: bool = true
# Equipped CANNON style. See scripts/weapons/WeaponStyle.gd for the
# enum. ENERGY (default Energy Blaster — blue muzzle, silent, infinite
# ammo), MACHINEGUN (brrrt loop, smoke + shells, limited ammo), or
# ROTARY_LASER (charge-up + ammo). Set by the equipped CANNON Part.
# Migrated from String to enum 2026-05-24 to eliminate the silent
# fallback bug where Parts forgot to set/restore the style.
var weapon_style: int = WS.WeaponStyle.ENERGY
# Per-cannon SFX tag — set by the equipped cannon's apply(). Routed to
# WeaponSfx.play() in fire_primary via WS.sfx_kind_string() so each weapon
# has its own sound. Migrated from String to enum 2026-05-24 to kill the
# silent fallback where an empty string implicitly routed through
# $ShootSound. NONE is now an explicit enum value, branched on below.
var fire_sfx_kind: int = WS.FireSfxKind.BLASTER_SMALL
# Ammo for the equipped CANNON. -1 means infinite (Energy Blaster). >= 0
# means counted (Machinegun). Outpost refills write here via Run.ammo.
var ammo: int = -1
signal ammo_changed(value: int)
# Rotary Laser recharge state. ammo_max and ammo_recharge_rate are written
# by RotaryLaserCannon.apply(); zeroed on unapply. _ammo_recharge_acc
# accumulates fractional shots so recharge is frame-rate independent.
var ammo_max: int = 0
var ammo_recharge_rate: float = 0.0
var _ammo_recharge_acc: float = 0.0
# Set false during intro/outro cinematics — _process still runs (so external
# tweens of position work), but input is ignored.
var controls_enabled: bool = true
const PlayerLoadoutCls = preload("res://scripts/weapons/loadout.gd")
const PartFactoryCls = preload("res://scripts/parts/part_factory.gd")

var loadout

# ---- Sci-Fi Shield FX ----
# Code-only ring sprite (no .tscn edit). Sits as a child of Player so it
# follows the ship; bullets still spawn at root.
const SHIELD_SHADER = preload("res://graphics/sci_fi_shield.gdshader")
var _shield_ring: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_alpha_tween: Tween = null
var _shield_hit_tween: Tween = null

# Machinegun audio — loop while firing, end SFX on release.
var _mg_loop_player: AudioStreamPlayer2D = null
var _mg_end_player: AudioStreamPlayer2D = null
var _mg_firing: bool = false

# Rotary Laser audio — charge → loop → release-shot.
const RL_CHARGE_DURATION: float = 0.4
var _rl_shoot_streams: Array = []
var _rl_charging: bool = false
var _rl_charged: bool = false
var _rl_charge_t: float = 0.0
var _rl_charge_player: AudioStreamPlayer2D = null
var _rl_loop_player: AudioStreamPlayer2D = null
var _rl_shoot_player_node: AudioStreamPlayer2D = null

# Particle Beam audio — charge → loop → stop (tap-fire skips loop+stop).
var _pb_charge_player: AudioStreamPlayer2D = null
var _pb_loop_player: AudioStreamPlayer2D = null
var _pb_stop_player: AudioStreamPlayer2D = null

@onready var screensize: Vector2 = get_viewport_rect().size

# Override target for spawned bullets/drones. Default null = parent at
# get_tree().root (live combat path). The Hangar dev tool runs the player
# inside a SubViewport and sets this to that viewport so projectiles stay
# in the same scene tree as the player + dummy target.
var bullet_parent: Node = null

func _bullet_parent() -> Node:
	return bullet_parent if bullet_parent != null else get_tree().root


func _ready() -> void:
	# Self-register in the "player" group so enemies (smart bomblets,
	# homing mines) can find us via get_nodes_in_group("player"). Without
	# this, the smart cluster mines could never see a target.
	if not is_in_group("player"):
		add_to_group("player")
	# Bump polyphony on the legacy fire SFX nodes so rapid shots don't
	# clip each other (Roman feedback 2026-05-23). Per-weapon SFX through
	# WeaponSfx already spawn fresh one-shots, but $ShootSound /
	# $CannonShoot / $SuperShoot are scene-embedded and cut themselves.
	var SfxCls = load("res://scripts/effects/sfx.gd")
	for sfx_name in ["ShootSound", "CannonShoot", "SuperShoot"]:
		if has_node(sfx_name):
			SfxCls.ensure_polyphony(get_node(sfx_name), 4)
	loadout = PlayerLoadoutCls.new()
	loadout.name = "Loadout"
	add_child(loadout)
	PartFactoryCls.default_starting_loadout(loadout)
	# Apply any parts the player bought / picked up between scenes. Run
	# stores them in `loadout_snapshot[slot] = part`; we equip on top of
	# the default loadout so a purchased CANNON / SHIELD / etc actually
	# shows up in combat (Roman, 2026-05-17: "they weren't actually being
	# added to the player ship when bought" — loadout_snapshot was never
	# being read into combat).
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			for slot in run.loadout_snapshot.keys():
				var part = run.loadout_snapshot[slot]
				if part != null:
					loadout.equip(int(slot), part)
	_setup_shield_ring()
	_setup_mg_audio()
	_setup_smoke_trail()
	# Ground shadow on the top parallax layer (Roman, 2026-05-16: ships
	# cast a drop shadow on first-layer parallax objects).
	var ParallaxShadow = load("res://scripts/effects/parallax_shadow.gd")
	ParallaxShadow.attach(self)
	# Oblique drop-shadow under the ship sprite (code-only; no .tscn edits).
	var ShadowFx = load("res://scripts/shadow_fx.gd")
	ShadowFx.attach_shadow($Ship)
	# Engine glow under the booster animation so the thrust reads as a
	# light source. Cyan-blue to match the booster art.
	var GlowFx = load("res://scripts/effects/glow_fx.gd")
	if $Ship.has_node("Boosters"):
		var booster: Node2D = $Ship.get_node("Boosters") as Node2D
		var glow = GlowFx.attach_glow($Ship, Color(0.45, 0.85, 1.0), 1.2, 0.75)
		glow.position = booster.position
	start()

func _setup_smoke_trail() -> void:
	# Sprite-based smoke trail (DamageSmokeTrail spawns one Sprite2D per puff,
	# tweens it downward + fading). Simpler and more reliable than the
	# CPUParticles2D approach which silently failed to render.
	var TrailCls = preload("res://scripts/effects/damage_smoke_trail.gd")
	var trail = TrailCls.new()
	trail.name = "DamageSmokeTrail"
	# Activate at any pip loss (hull spec 2026-05-26): player uses 0.01 so
	# even losing 1 of 3 pips (damage_level ≈ 0.33) triggers the effects.
	trail.activate_below = 0.01
	add_child(trail)
	trail.set_player(self)
	# Procedural torch fire on the engine nozzle (Roman 2026-05-18). Reads
	# horizontal velocity each frame and pipes it into the shader's
	# windForce so the flame leans opposite the direction of travel.
	var EngineTorchCls = preload("res://scripts/effects/engine_torch.gd")
	EngineTorchCls.attach_to_player(self, EngineTorchCls.NOZZLE_OFFSET_DEFAULT, 0.01)


func _setup_mg_audio() -> void:
	# Two AudioStreamPlayer2D nodes: the loop runs while the trigger is held,
	# the end SFX punctuates the release.
	#
	# Roman, 2026-05-16: "apply a modest low-pass filter." Earlier attempt to
	# install a runtime "Weapons" bus with a LowPassFilter killed all audio in
	# the build — root cause never confirmed but the bus mutation was the only
	# suspect. To dodge that entirely, the filter is *pre-baked* into the OGG
	# (ffmpeg `lowpass=f=4000`). The `-LP.ogg` files are committed alongside
	# the originals. pitch_scale is dialed back closer to neutral now that the
	# muffle character comes from the filter instead of pitch.
	var loop_stream: AudioStream = load("res://Sound/weapons/Machinegun-Loop-LP.ogg")
	if loop_stream is AudioStreamOggVorbis:
		(loop_stream as AudioStreamOggVorbis).loop = true
	_mg_loop_player = AudioStreamPlayer2D.new()
	_mg_loop_player.name = "MgLoop"
	_mg_loop_player.stream = loop_stream
	_mg_loop_player.volume_db = -3.0
	_mg_loop_player.pitch_scale = 0.92
	add_child(_mg_loop_player)

	var end_stream: AudioStream = load("res://Sound/weapons/Machinegun-End-LP.ogg")
	_mg_end_player = AudioStreamPlayer2D.new()
	_mg_end_player.name = "MgEnd"
	_mg_end_player.stream = end_stream
	_mg_end_player.volume_db = -3.0
	_mg_end_player.pitch_scale = 0.92
	add_child(_mg_end_player)
	# Rotary Laser audio nodes come from the player scene.
	_rl_charge_player = get_node_or_null("RotaryLaserCharge")
	_rl_loop_player = get_node_or_null("RotaryLaserLoop")
	_rl_shoot_player_node = get_node_or_null("RotaryLaserShoot")
	_rl_shoot_streams = [
		load("res://Sound/weapons/rotary_laser_shoot_1.ogg"),
		load("res://Sound/weapons/rotary_laser_shoot_2.ogg"),
		load("res://Sound/weapons/rotary_laser_shoot_3.ogg"),
		load("res://Sound/weapons/rotary_laser_shoot_4.ogg"),
		load("res://Sound/weapons/rotary_laser_shoot_5.ogg"),
		load("res://Sound/weapons/rotary_laser_shoot_6.ogg"),
	]
	if _rl_loop_player:
		var ls: AudioStream = _rl_loop_player.stream
		if ls is AudioStreamOggVorbis:
			(ls as AudioStreamOggVorbis).loop = true
	_pb_charge_player = get_node_or_null("ParticleBeamCharge")
	_pb_loop_player = get_node_or_null("ParticleBeamLoop")
	_pb_stop_player = get_node_or_null("ParticleBeamStop")
	if _pb_loop_player:
		var pls: AudioStream = _pb_loop_player.stream
		if pls is AudioStreamOggVorbis:
			(pls as AudioStreamOggVorbis).loop = true


func _rl_stop() -> void:
	var was_charged := _rl_charged
	_rl_charging = false
	_rl_charged = false
	_rl_charge_t = 0.0
	if _rl_charge_player and _rl_charge_player.playing:
		_rl_charge_player.stop()
	if _rl_loop_player and _rl_loop_player.playing:
		_rl_loop_player.stop()
	if was_charged and is_alive and _rl_shoot_player_node and not _rl_shoot_streams.is_empty():
		_rl_shoot_player_node.stream = _rl_shoot_streams[randi() % _rl_shoot_streams.size()]
		_rl_shoot_player_node.play()


func _setup_shield_ring() -> void:
	# ColorRect is a Control; size in local space. Player is scaled 3x by its
	# parent, so 26 local px = 78 screen px ring diameter (comfortably wraps the
	# 16x16 ship).
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.0)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)

	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1) # shader drives final color
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_ring.size = Vector2(26, 26)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)

func start() -> void:
	show()
	is_alive = true
	position = Vector2(Playfield.CENTER.x, screensize.y - 30)
	# Run-level upgrades (outpost purchases) feed into max_hull, max_shield,
	# and speed_multiplier here so every combat scene picks up the latest state.
	apply_run_upgrades()
	shield = max_shield  # combat level starts fully-shielded
	# Hull loaded from Run.current_hull via start() context (set in apply_run_upgrades).
	can_shoot = true
	$GunCooldown.wait_time = cooldown
	# Shield regen: always full at combat start — no timer needed.
	_shield_in_delay = false
	$ShieldRegenTimer.stop()
	# Restore super_charges from Run (persisted across scenes) — parts'
	# apply() already set max during _ready, so we just overwrite the
	# current charge count with whatever was saved. Run.super_charges
	# starts at 0 on new_run, but the part's initial apply has already
	# populated max_super_charges and run.super_charges (via the part).
	# Use the larger of the two on first combat so we start with full
	# charges.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "super_charges" in run and "max_super_charges" in run:
			if int(run.super_charges) <= 0 and run.super_charges < max_super_charges:
				# Fresh run — keep the full charges the part assigned and
				# sync Run so the snapshot starts off correct.
				run.super_charges = super_charges
				run.max_super_charges = max_super_charges
			else:
				# Returning from a meta scene with partial charges spent.
				super_charges = clampi(int(run.super_charges), 0, max_super_charges)
				super_charges_changed.emit(super_charges, max_super_charges)
	# Force-emit UI updates so bars reflect current loadout
	shield_changed.emit(max_shield, shield)
	hull_changed.emit(max_hull, hull)
	# Initial shield-ring visibility matches starting shield.
	_set_shield_ring_alpha(1.0 if shield > 0 else 0.0, 0.0)

func _process(delta: float) -> void:
	if not is_alive:
		return
	if _invuln_t > 0.0:
		_invuln_t = max(0.0, _invuln_t - delta)
	# Secondary cooldown ticks every frame regardless of input — so the
	# weapon recharges in the background and a tap fires immediately
	# whenever it's ready.
	_secondary_t = min(_secondary_t + delta, secondary_cooldown)
	if _hyper_t > 0.0:
		_hyper_t = max(0.0, _hyper_t - delta)
		# While hyper is active, bypass GunCooldown so primary fires every
		# frame. Damage gets scaled inside fire_primary below.
		can_shoot = true
	if not controls_enabled:
		# Ship still animates "forward" so it reads as actively flying during
		# the intro slide-in / outro fly-out cinematic.
		$Ship.frame = 1
		$Ship/Boosters.animation = "forward"
		# Stop any in-flight machinegun audio so the loop doesn't keep
		# brrrt'ing while the player is flying off-screen at level end
		# (Roman, 2026-05-16: "make sure to stop them shooting").
		if _mg_firing:
			_mg_firing = false
			if _mg_loop_player and _mg_loop_player.playing:
				_mg_loop_player.stop()
		return
	var input := Input.get_vector("left", "right", "up", "down")
	if input.x > 0:
		$Ship.frame = 2
		$Ship/Boosters.animation = "right"
	elif input.x < 0:
		$Ship.frame = 0
		$Ship/Boosters.animation = "left"
	else:
		$Ship.frame = 1
		$Ship/Boosters.animation = "forward"
	# Focus mode (Shift, by convention): ⅔-ish speed for precision
	# dodging + show the hitbox dot so the player sees their collider.
	var focused: bool = Input.is_action_pressed("focus")
	var focus_mult: float = FOCUS_FACTOR if focused else 1.0
	_update_focus_dot(focused)
	# Thrusters / Armor Plating upgrades feed into speed_multiplier;
	# applied here so the runtime stat reflects the live upgrade state.
	position += input * speed * speed_multiplier * focus_mult * delta
	position = Playfield.clamp_pos(position, 8.0)
	# Autofire toggle (Settings.autofire) latches primary fire on so
	# players don't have to hold the button. Holding still works
	# explicitly when autofire is off. The "autofire_toggle" action (R)
	# flips Settings.autofire at runtime and surfaces a brief toast so
	# the player sees the new state without opening the options menu.
	if Input.is_action_just_pressed("autofire_toggle") and has_node("/root/Settings"):
		var s_toggle = get_node("/root/Settings")
		if s_toggle.has_method("set_autofire"):
			var new_state: bool = not bool(s_toggle.autofire)
			s_toggle.set_autofire(new_state)
			_show_autofire_toast(new_state)
	var fire_held: bool = Input.is_action_pressed("shoot")
	if not fire_held and has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if "autofire" in s and s.autofire:
			fire_held = true
	# Primary swap (Weapons Phase 1, Q): flip between blaster (cannon_pool[0])
	# and the last-used replacement primary. Re-applies the new active cannon
	# to the ship so bullet_scene / cooldown / damage all swap atomically.
	if Input.is_action_just_pressed("primary_swap"):
		_swap_active_primary()
	if fire_held:
		fire_primary()
		# MG audio loop only when the machinegun is the equipped CANNON
		# AND there's still ammo. Energy blaster fire is silent.
		if weapon_style == WS.WeaponStyle.MACHINEGUN and ammo != 0 and not _mg_firing and is_alive:
			_mg_firing = true
			if _mg_loop_player and not _mg_loop_player.playing:
				_mg_loop_player.play()
		# Rotary Laser: charge → loop → fire.
		elif weapon_style == WS.WeaponStyle.ROTARY_LASER and ammo > 0 and is_alive:
			if not _rl_charging and not _rl_charged:
				_rl_charging = true
				_rl_charge_t = 0.0
				if _rl_charge_player:
					_rl_charge_player.play()
			elif _rl_charging:
				_rl_charge_t += delta
				if _rl_charge_t >= RL_CHARGE_DURATION:
					_rl_charging = false
					_rl_charged = true
					if _rl_loop_player:
						_rl_loop_player.play()
	elif _mg_firing:
		_mg_firing = false
		if _mg_loop_player and _mg_loop_player.playing:
			_mg_loop_player.stop()
		if _mg_end_player and is_alive and weapon_style == WS.WeaponStyle.MACHINEGUN:
			_mg_end_player.play()
	if not fire_held and (_rl_charging or _rl_charged):
		_rl_stop()
	# Rotary Laser ammo recharge — ticks when not firing. Players who have
	# autofire enabled will never recharge while alive on screen (same
	# behaviour as the machinegun: continuous trigger = no pause to refill).
	if ammo_recharge_rate > 0.0 and ammo_max > 0 and ammo < ammo_max and not Input.is_action_pressed("shoot"):
		_ammo_recharge_acc += ammo_recharge_rate * delta
		var to_add: int = int(_ammo_recharge_acc)
		if to_add >= 1:
			_ammo_recharge_acc -= float(to_add)
			ammo = min(ammo + to_add, ammo_max)
			ammo_changed.emit(ammo)
			if has_node("/root/Run"):
				get_node("/root/Run").ammo = ammo
	# Secondary fire (C by default, hold-fire). Beam mode is held-tick
	# per-frame; bullet mode spawns a projectile per cooldown window.
	if secondary_mode == WS.SecondaryMode.BEAM:
		var holding: bool = Input.is_action_pressed("shoot2")
		_tick_beam(holding, delta)
	elif Input.is_action_pressed("shoot2"):
		fire_secondary()
	# Super weapon (X by default, single-tap, consumes a charge). Stub
	# until DEVICE_BAY slot Parts implement themselves.
	if Input.is_action_just_pressed("shoot_nose"):
		fire_super()

# ---- Damage pipeline ----
# Shield is an HP pool — full bullet damage absorbed, no overflow to hull.
# Hull is pip-based — 1 pip per hit when shield is empty.
# Hull == 0 → pips flash; NEXT hit fires super-bomb then kills.
# Spec 2026-05-26 rework.
func take_damage(amount: int) -> void:
	if not is_alive or amount <= 0:
		return
	# "dangerous" sector modifier doubles all incoming enemy damage.
	# Per-sector difficulty scaler: incoming damage scales × (1 + 0.05 × sectors_cleared).
	if has_node("/root/Run"):
		var _run = get_node("/root/Run")
		if "sector_modifiers" in _run and "dangerous" in _run.sector_modifiers:
			amount *= 2
		if "sectors_cleared" in _run:
			var sector_mult: float = 1.0 + 0.05 * float(_run.sectors_cleared)
			amount = int(round(float(amount) * sector_mult))
	# I-frame window after a shield or hull hit.
	if _invuln_t > 0.0:
		return
	var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
	if shield > 0:
		# Shield absorbs full hit — no overflow to hull.
		set_shield(max(0, shield - amount))
		_invuln_t = SHIELD_INVULN_SECONDS
		damaged.emit(0)
		_pulse_shield_ring()
		if has_node("Ship"):
			HitFlashFx.flash($Ship, HitFlashFx.FLASH_SHIELD)
		return
	# Shield empty — hull takes a binary 1-pip hit.
	if hull <= 0:
		# Already at zero pips — kill hit. Super-bomb fires first if available.
		if super_charges > 0 and super_part != null:
			fire_super()
			# Super sets _invuln_t; if so, we survive this hit.
			if _invuln_t > 0.0:
				return
		damaged.emit(1)
		set_hull(0)
		die()
		return
	# Normal hull pip loss (hull > 0, shield == 0).
	damaged.emit(1)
	_invuln_t = SHIELD_INVULN_SECONDS
	if has_node("Ship"):
		HitFlashFx.flash($Ship, HitFlashFx.FLASH_WHITE)
	set_hull(hull - 1)

func set_shield(value: int) -> void:
	var prev := shield
	shield = clampi(value, 0, max_shield)
	shield_changed.emit(max_shield, shield)
	# Roman, 2026-05-18: shield-hit / shield-break SFX. Only on DRAINS
	# (regen ticks back up silently). Break plays when the last charge
	# is consumed; otherwise it's a normal hit.
	if prev > shield:
		var ShieldSfx = load("res://scripts/effects/shield_sfx.gd")
		if ShieldSfx:
			if shield == 0:
				ShieldSfx.play_break(get_tree().root, global_position)
			else:
				ShieldSfx.play_hit(get_tree().root, global_position)
		# Cobalt 2026-05-21: animated shield_hit / shield_break sprite at
		# the shield center on each drain. Break plays only when the last
		# charge is consumed.
		if shield == 0:
			_play_shield_anim(SHIELD_BREAK_TEX)
		else:
			_play_shield_anim(SHIELD_HIT_TEX)
	# Regen: 5s delay after any hit, then 1/sec ticks until full.
	if prev > shield:
		# Hit — restart 5s regen delay.
		_shield_in_delay = true
		if has_node("ShieldRegenTimer"):
			$ShieldRegenTimer.stop()
			$ShieldRegenTimer.wait_time = 5.0
			$ShieldRegenTimer.start()
	elif shield >= max_shield and has_node("ShieldRegenTimer"):
		# At cap — halt regen.
		_shield_in_delay = false
		$ShieldRegenTimer.stop()
	# FX gates — the shield ring is visible only while we have charges.
	if has_node("ImpactParticle"):
		$ImpactParticle.restart()
	if has_node("Ship/Shield/ShieldFlash"):
		$Ship/Shield/ShieldFlash.play()
	if prev > 0 and shield == 0:
		_set_shield_ring_alpha(0.0, 0.3)
	elif prev == 0 and shield > 0:
		_set_shield_ring_alpha(1.0, 0.25)

func set_hull(value: int) -> void:
	hull = clampi(value, 0, max_hull)
	hull_changed.emit(max_hull, hull)
	$ImpactParticle.restart()
	# Death is triggered from take_damage, not here. hull == 0 means
	# flashing pips; the kill hit (next hit at hull == 0) calls die() explicitly.

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	hide()
	died.emit()
	$ShieldRegenTimer.stop()
	$GunCooldown.stop()
	can_shoot = false
	# Cut the MG loop the moment we die — otherwise the audio outlives the
	# player by half a second of "...brrrt".
	if _mg_loop_player and _mg_loop_player.playing:
		_mg_loop_player.stop()
	_mg_firing = false
	_rl_charging = false
	_rl_charged = false
	if _rl_charge_player and _rl_charge_player.playing:
		_rl_charge_player.stop()
	if _rl_loop_player and _rl_loop_player.playing:
		_rl_loop_player.stop()
	$Death.play()

# ---- Fire paths ----
# Primary fire is driven by the CANNON slot Part. Secondary fire will be
# driven by hardpoint/device parts (Phase 2+); for now it's a hook only.
func fire_primary() -> void:
	if not can_shoot or bullet_scene == null:
		return
	# Weapons Phase 1: every non-blaster primary is metered. Active cannon
	# index 0 == blaster (infinite); anything else has a magazine that lives
	# on the Part instance in Run.cannon_pool[active_cannon_idx].current_ammo.
	# The player's `ammo` field mirrors that for HUD/SFX gating.
	if _is_replacement_primary_active() and ammo == 0:
		# Out of ammo on a non-blaster — snap back to blaster (defensive;
		# normally happens at the moment ammo hits 0 below). Skip this
		# shot; next fire will use the blaster.
		_snap_to_blaster_and_reapply()
		return
	# Rotary Laser: also charge-gated.
	if weapon_style == WS.WeaponStyle.ROTARY_LASER and not _rl_charged:
		return
	can_shoot = false
	$GunCooldown.start()
	# Cobalt 2026-05-21 follow-up: emit from the top-center of the player
	# sprite, slightly AHEAD of the ship (above the top edge). Ship is
	# 16×16 centered; top edge sits at local Y=-8, so (-0, -10) is two
	# pixels ahead of the leading edge.
	var muzzle_pos: Vector2 = global_position + Vector2(0, -10)
	# Spread support — Spread Cannon Part sets bullet_spread_count > 1.
	# Default 1 fires straight up exactly as before. For N > 1, fan the
	# bullets out across bullet_spread_degrees, centred straight up.
	var count: int = max(1, bullet_spread_count)
	var spread_rad: float = deg_to_rad(bullet_spread_degrees)
	for i in range(count):
		var angle: float = 0.0
		if count > 1:
			var t: float = float(i) / float(count - 1)
			angle = -spread_rad * 0.5 + spread_rad * t
		# 0 angle = straight up. (sin(a), -cos(a)) rotates around the up axis.
		var dir := Vector2(sin(angle), -cos(angle))
		var b: Node = bullet_scene.instantiate()
		_bullet_parent().add_child(b)
		# Propagate the equipped cannon's damage to the bullet so per-Part /
		# per-Mark scaling actually reaches the take_hit call.
		# Hyper Mode doubles damage for its duration.
		if "damage" in b:
			var dmg: int = bullet_damage
			if _hyper_t > 0.0:
				dmg = int(round(float(bullet_damage) * HYPER_DAMAGE_MULT))
			b.damage = dmg
		# Per-cannon overrides (Wave Gun speed + pierce, etc). Sentinel
		# < 0 / <= 0 leaves the bullet scene's own export default alone.
		if bullet_speed_override > 0.0 and "speed" in b:
			b.speed = bullet_speed_override
		if bullet_max_hits_override > 0 and "max_hits" in b:
			b.max_hits = bullet_max_hits_override
		# Auto Laser tandem fire: alternate L/R 8px from the player center
		# on each shot. Only applies to single-shot cannons (count == 1).
		# Slide the muzzle flash position with the spawn so the rotary
		# laser flash sits over the bolt, not at center.
		var spawn_offset: Vector2 = Vector2(0, -8)
		if fire_tandem_alternating and count == 1:
			var side_x: float = -8.0 if _tandem_side == 0 else 8.0
			spawn_offset = Vector2(side_x, -8)
			muzzle_pos = global_position + Vector2(side_x, -10)
			_tandem_side = 1 - _tandem_side
		b.start(position + spawn_offset, dir)
	# Drone Bits piggyback the primary fire — one extra bullet from each
	# drone's position, fired straight up. Uses drone_bits_bullet_scene
	# (defaults to the primary's bullet if not set) and drone damage.
	if drone_bits and drone_bits.size() > 0:
		var drone_scene: PackedScene = drone_bits_bullet_scene if drone_bits_bullet_scene else bullet_scene
		if drone_scene:
			for drone in drone_bits:
				if not is_instance_valid(drone):
					continue
				var db: Node = drone_scene.instantiate()
				_bullet_parent().add_child(db)
				if "damage" in db:
					db.damage = drone_bits_damage
				db.start(drone.global_position + Vector2(0, -4))
	# Style-specific muzzle FX + per-shot SFX.
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	if weapon_style == WS.WeaponStyle.MACHINEGUN:
		MuzzleFx.play(muzzle_pos, self)  # flash parented to player
	elif weapon_style == WS.WeaponStyle.ROTARY_LASER:
		MuzzleFx.play_rotary_laser(muzzle_pos, self)
	else:
		# Auto Laser et al. piggyback the rotary laser muzzle flash even
		# though they're ENERGY-style (no ammo/charge gate). Branch on
		# the explicit flag so we don't have to expand WeaponStyle.
		if use_rotary_laser_muzzle:
			MuzzleFx.play_rotary_laser(muzzle_pos, self)
		else:
			MuzzleFx.play_energy(muzzle_pos, self)
		# Per-shot cannon SFX, dispatched by the equipped cannon's
		# fire_sfx_kind enum. NONE explicitly falls through to the legacy
		# ShootSound (e.g., Auto Laser — placeholder until dedicated SFX
		# land). See WS.FireSfxKind / WS.sfx_kind_string.
		var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
		if WeaponSfx and fire_sfx_kind != WS.FireSfxKind.NONE:
			WeaponSfx.play(get_tree().root, global_position, WS.sfx_kind_string(fire_sfx_kind))
		elif has_node("ShootSound"):
			$ShootSound.play()
	var tween := create_tween().set_parallel(false)
	tween.tween_property($Ship, "position:y", 1, 0.1)
	tween.tween_property($Ship, "position:y", 0, 0.05)
	# Weapons Phase 1: every non-blaster primary deducts ONE ammo per fire.
	# The blaster (cannon_pool[0]) has ammo == -1 and is skipped. When ammo
	# hits 0, snap to the blaster and re-apply on the next frame so the
	# WeaponPart.apply/unapply snapshot cycle happens cleanly outside the
	# fire loop.
	if _is_replacement_primary_active() and ammo > 0:
		ammo -= 1
		ammo_changed.emit(ammo)
		# Mirror to the active cannon Part so the magazine survives swap-out.
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			run.ammo = ammo
			var active = run.get_active_cannon()
			if active != null and "current_ammo" in active:
				active.current_ammo = ammo
		if ammo == 0:
			# Defer the swap so we don't mutate loadout mid-fire (WeaponPart
			# apply/unapply rewrites bullet_scene/cooldown/etc).
			call_deferred("_snap_to_blaster_and_reapply")


# True when active_cannon_idx != 0 (non-blaster). Centralizes the "is
# this a metered/replacement primary?" check so fire_primary and the
# swap path stay in agreement (no silent fallbacks).
func _is_replacement_primary_active() -> bool:
	if not has_node("/root/Run"):
		return false
	var run = get_node("/root/Run")
	return int(run.active_cannon_idx) != 0


# Snap the active cannon back to cannon_pool[0] (blaster) and re-apply it
# through the loadout system so bullet_scene / cooldown / damage / SFX all
# revert. Called when ammo hits 0 OR when the player presses primary_swap.
func _snap_to_blaster_and_reapply() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	run.swap_to_blaster()
	_reapply_active_cannon()


# Re-apply whatever Run.get_active_cannon() points at to the player ship.
# The loadout's equip() runs unapply on the prior CANNON part (restoring
# its snapshot) then apply on the new one. Safe to call any time outside
# fire_primary's tight loop.
func _reapply_active_cannon() -> void:
	if not has_node("/root/Run") or loadout == null:
		return
	var run = get_node("/root/Run")
	var active = run.get_active_cannon()
	if active == null:
		return
	const Slots = preload("res://scripts/weapons/SlotTypes.gd")
	loadout.equip(Slots.SlotType.CANNON, active)


# Toggle the active primary. Q-bound; routes to Run.cycle_primary() and
# re-applies. No-op if the player only owns the blaster.
func _swap_active_primary() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.cannon_pool.size()) <= 1:
		return
	run.cycle_primary()
	_reapply_active_cannon()


# Ammo setter for the CANNON Part to plumb its starting ammo. Public so
# Outpost / Junk Trader refill paths can also call it directly.
func set_ammo(value: int) -> void:
	ammo = value
	ammo_changed.emit(ammo)
	if has_node("/root/Run"):
		get_node("/root/Run").ammo = ammo


# Secondary ammo setter — called by Rocket Pod / Seeking Missile Part on
# apply(), and by the future shop refill flow. value < 0 disables metering
# (unmetered Side Pods / Particle Beam state). maximum < 0 is treated as
# "match value" so callers that don't care about cap don't have to pass it.
func set_secondary_ammo(value: int, maximum: int = -1) -> void:
	secondary_ammo = value
	if maximum >= 0:
		secondary_ammo_max = maximum
	elif value >= 0 and secondary_ammo_max < 0:
		secondary_ammo_max = value
	if value < 0:
		secondary_ammo_max = -1
	secondary_ammo_changed.emit(secondary_ammo, secondary_ammo_max)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.secondary_ammo = secondary_ammo
		run.secondary_ammo_max = secondary_ammo_max

func fire_secondary() -> void:
	# HARDPOINT_WING Parts (Seeking Missile, Rocket Pod, Side Pods) write
	# to secondary_bullet_scene / cooldown / damage / pod_count in their
	# apply(). One cooldown tick spawns secondary_pod_count bullets
	# evenly distributed across ±halfspan.
	if secondary_bullet_scene == null:
		return
	if not is_alive:
		return
	if _secondary_t < secondary_cooldown:
		return
	# Ammo gate — only applies to metered secondaries (Rocket Pod / Seeking
	# Missile set secondary_ammo_max > 0). Unmetered (-1) fires forever.
	if secondary_ammo == 0:
		return
	_secondary_t = 0.0
	var count: int = max(1, secondary_pod_count)
	for i in count:
		var offset_x: float = 0.0
		if count > 1:
			# Spread evenly from -halfspan to +halfspan.
			var t: float = float(i) / float(count - 1)
			offset_x = -secondary_pod_halfspan + secondary_pod_halfspan * 2.0 * t
		var b: Node = secondary_bullet_scene.instantiate()
		_bullet_parent().add_child(b)
		if "damage" in b:
			b.damage = secondary_damage
		if secondary_homing and "guided" in b:
			b.guided = true
		# Wing-offset spawn position so multi-pod fire reads as
		# "wingtip muzzles" rather than a stack of nose-mounted bolts.
		b.start(position + Vector2(offset_x, -10))
	var WeaponSfxSec = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfxSec:
		var kind: String = "missile" if secondary_homing else "rocket"
		WeaponSfxSec.play(get_tree().root, global_position, kind)
	# Decrement ONE per fire_secondary press regardless of pod_count — the
	# pod_count is a visual fan, not a per-shot multiplier on ammo cost.
	# (If we ever want pod_count to cost N rounds, change here.)
	if secondary_ammo > 0:
		secondary_ammo -= 1
		secondary_ammo_changed.emit(secondary_ammo, secondary_ammo_max)
		if has_node("/root/Run"):
			get_node("/root/Run").secondary_ammo = secondary_ammo


## Continuous Particle Beam ##

# Build the Line2D lazily on first beam tick. Stored as a child of the
# player so it inherits transforms — beam endpoints are in LOCAL coords
# (player origin = 0,0; muzzle slightly above).
func _ensure_beam_visual() -> void:
	if _beam_line and is_instance_valid(_beam_line):
		return
	# Halo — wide, low-alpha teal "glow." Drawn first so the main beam
	# overlays it. Width is sized in _tick_beam based on current beam_width.
	var halo := Line2D.new()
	halo.name = "ParticleBeamHalo"
	halo.default_color = Color(0.35, 0.85, 1.0, 0.35)
	halo.begin_cap_mode = Line2D.LINE_CAP_ROUND
	halo.end_cap_mode = Line2D.LINE_CAP_ROUND
	halo.z_index = 4
	halo.visible = false
	# Main beam — teal/cyan, full alpha.
	var line := Line2D.new()
	line.name = "ParticleBeam"
	line.default_color = Color(0.55, 0.95, 1.0, 1.0)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5
	line.visible = false
	# Core — narrow, white hot center.
	var core := Line2D.new()
	core.name = "ParticleBeamCore"
	core.default_color = Color(1.0, 1.0, 1.0, 1.0)
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	core.z_index = 6
	core.visible = false
	# Deferred adds avoid "parent busy" during the first tick after equip.
	if is_inside_tree():
		add_child.call_deferred(halo)
		add_child.call_deferred(line)
		add_child.call_deferred(core)
	else:
		add_child(halo)
		add_child(line)
		add_child(core)
	_beam_halo = halo
	_beam_line = line
	_beam_core = core


# Spawn the beam flash sprite at the player's muzzle and put it into
# WARMUP. Lives until cool-down completes.
func _begin_beam_flash() -> void:
	if _beam_flash and is_instance_valid(_beam_flash):
		_beam_flash.queue_free()
	var s := Sprite2D.new()
	s.name = "BeamFlash"
	s.texture = BEAM_FLASH_TEX
	s.hframes = BEAM_FLASH_HFRAMES
	s.frame = 0
	s.position = Vector2(0, -10)  # muzzle
	s.z_index = 7  # over halo(4)/line(5)/core(6)
	add_child(s)
	_beam_flash = s
	_beam_flash_state = BeamFlashState.WARMUP
	_beam_flash_frame_t = 0.0
	if _pb_charge_player:
		_pb_charge_player.play()


# Per-frame state machine for the flash sprite. Advances WARMUP frames,
# jitters HOLD frame, advances COOLDOWN frames, then frees the sprite.
func _tick_beam_flash(delta: float) -> void:
	if _beam_flash == null or not is_instance_valid(_beam_flash):
		return
	_beam_flash_frame_t += delta
	match _beam_flash_state:
		BeamFlashState.WARMUP:
			# Frames 0..(BEAM_HOLD_FRAME-1) over BEAM_WARMUP_TIME.
			var target_frame: int = clampi(int(_beam_flash_frame_t / BEAM_FRAME_TIME_WARMUP), 0, BEAM_HOLD_FRAME - 1)
			_beam_flash.frame = target_frame
			if _beam_flash_frame_t >= BEAM_WARMUP_TIME:
				_beam_flash_state = BeamFlashState.HOLD
				_beam_flash_frame_t = 0.0
				_beam_flash.frame = BEAM_HOLD_FRAME
				if _pb_charge_player and _pb_charge_player.playing:
					_pb_charge_player.stop()
				if _pb_loop_player:
					_pb_loop_player.play()
		BeamFlashState.HOLD:
			# Hold on BEAM_HOLD_FRAME with a subtle scale jitter.
			_beam_flash.frame = BEAM_HOLD_FRAME
			var jitter: float = 1.0 + 0.12 * sin(_beam_flash_frame_t * TAU * 6.0)
			_beam_flash.scale = Vector2(jitter, jitter)
		BeamFlashState.COOLDOWN:
			# Frames (HOLD+1)..(HFRAMES-1) over BEAM_COOLDOWN_TIME, then free.
			_beam_flash.scale = Vector2.ONE
			var idx: int = BEAM_HOLD_FRAME + 1 + int(_beam_flash_frame_t / BEAM_FRAME_TIME_COOLDOWN)
			_beam_flash.frame = clampi(idx, BEAM_HOLD_FRAME + 1, BEAM_FLASH_HFRAMES - 1)
			if _beam_flash_frame_t >= BEAM_COOLDOWN_TIME:
				_beam_flash.queue_free()
				_beam_flash = null
				_beam_flash_state = BeamFlashState.NONE
		_:
			pass


# Shield hit / break sprite playback (Cobalt 2026-05-21). Spawns a
# Sprite2D at the player's shield ring, plays the strip across 5 frames
# over ~0.4s, frees itself. `texture` is the sprite strip with hframes
# set; both shield_hit and shield_break are 5-frame strips.
const SHIELD_HIT_TEX = preload("res://graphics/shield_hit.png")
const SHIELD_BREAK_TEX = preload("res://graphics/shield_break.png")
const SHIELD_ANIM_HFRAMES := 5
const SHIELD_ANIM_DURATION := 0.4
const SHIELD_ANIM_FRAME_TIME := SHIELD_ANIM_DURATION / float(SHIELD_ANIM_HFRAMES)
# Dedupe guard. set_shield can fire twice in one frame (e.g., setter
# recursion via the property's `set =` hook), or back-to-back hits inside
# a single physics tick before the previous anim has visually started.
# Skip any call within this many ms of the previous one.
const SHIELD_ANIM_MIN_INTERVAL_MS := 80
var _shield_anim_last_ms: int = 0

func _play_shield_anim(tex: Texture2D) -> void:
	if tex == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _shield_anim_last_ms < SHIELD_ANIM_MIN_INTERVAL_MS:
		return
	_shield_anim_last_ms = now_ms
	var s := Sprite2D.new()
	s.name = "ShieldAnim"
	s.texture = tex
	s.hframes = SHIELD_ANIM_HFRAMES
	s.frame = 0
	# Anchor on the Ship's shield ring (centered on the ship sprite).
	if has_node("Ship"):
		$Ship.add_child(s)
		s.position = Vector2.ZERO
	else:
		add_child(s)
	s.z_index = 6
	# Drive frame index via a tween — simple, no need for a per-frame loop.
	var tw := create_tween()
	# Tween the frame property as a float; setter rounds.
	tw.tween_method(
		func(v: float):
			if is_instance_valid(s):
				s.frame = clampi(int(v), 0, SHIELD_ANIM_HFRAMES - 1),
		0.0,
		float(SHIELD_ANIM_HFRAMES - 1),
		SHIELD_ANIM_DURATION,
	)
	tw.tween_callback(s.queue_free)


# Per-frame: scan enemies in a vertical column above the player, sorted
# by Y descending so we hit the nearest first. Pierce through any enemy
# that ISN'T flagged tough/boss; stop on the first tough/boss enemy.
# Damage applied = secondary_beam_dps × delta to every enemy in the path.
const TOUGH_HP_THRESHOLD := 8  # enemies with > 8 max_hull count as "tough"


func _tick_beam(holding: bool, delta: float) -> void:
	_ensure_beam_visual()
	# Drive the flash sprite state machine. The beam itself only fires
	# during HOLD; during WARMUP we play the windup frames and the beam
	# lines stay hidden. On release we kick into COOLDOWN frames before
	# tearing the sprite down.
	if not holding or not is_alive:
		# Released (or died). Switch active beam → cool-down.
		if _beam_active:
			_beam_active = false
			if _beam_halo: _beam_halo.visible = false
			if _beam_line: _beam_line.visible = false
			if _beam_core: _beam_core.visible = false
			if _beam_flash and is_instance_valid(_beam_flash) and _beam_flash_state == BeamFlashState.HOLD:
				_beam_flash_state = BeamFlashState.COOLDOWN
				_beam_flash_frame_t = 0.0
				_beam_flash.frame = BEAM_HOLD_FRAME
			# Was firing — stop loop, play stop sound.
			if _pb_loop_player and _pb_loop_player.playing:
				_pb_loop_player.stop()
			if _pb_stop_player:
				_pb_stop_player.play()
		elif _beam_flash_state == BeamFlashState.WARMUP:
			# Tap-fire: released during warmup — stop charge, skip loop+stop.
			if _pb_charge_player and _pb_charge_player.playing:
				_pb_charge_player.stop()
		_tick_beam_flash(delta)
		return
	# Holding. If no flash yet, kick off WARMUP.
	if _beam_flash == null or not is_instance_valid(_beam_flash):
		_begin_beam_flash()
	_tick_beam_flash(delta)
	# Beam only actually fires during HOLD — suppress during WARMUP.
	if _beam_flash_state != BeamFlashState.HOLD:
		if _beam_halo: _beam_halo.visible = false
		if _beam_line: _beam_line.visible = false
		if _beam_core: _beam_core.visible = false
		return
	_beam_active = true
	if _beam_halo: _beam_halo.visible = true
	if _beam_line: _beam_line.visible = true
	if _beam_core: _beam_core.visible = true
	# Width drives the visual AND the hit-column tolerance. Halo bloats
	# 60% wider than main; core is 35% as wide for a hot center.
	if _beam_line:
		_beam_line.width = secondary_beam_width
	if _beam_halo:
		_beam_halo.width = secondary_beam_width * 1.6
	if _beam_core:
		_beam_core.width = max(1.0, secondary_beam_width * 0.35)
	var beam_half_width: float = secondary_beam_width * 0.5 + 2.0
	# Find the first tough/boss enemy in the beam's column; that's where
	# the beam stops. Soft enemies between us and it get damaged.
	var tree := get_tree()
	if tree == null:
		return
	var enemies_in_column: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip enemies BELOW the player or outside the beam's x band.
		if e.global_position.y > global_position.y:
			continue
		if abs(e.global_position.x - global_position.x) > beam_half_width:
			continue
		enemies_in_column.append(e)
	enemies_in_column.sort_custom(_sort_by_y_desc)
	# DPS × delta — frame-rate independent. At 60 fps + 30 DPS that
	# rounds to 1 dmg/tick (since int(round(0.5)) = 1 on tied rounding,
	# but max(1, ...) guards anyway).
	var dmg_amount: int = max(1, int(round(secondary_beam_dps * delta)))
	var stop_y: float = -screensize.y  # default: top of world
	for e in enemies_in_column:
		if e.has_method("take_hit"):
			e.take_hit(dmg_amount)
		if _is_tough_or_boss(e):
			# Beam stops here — set end point at the enemy's Y, exit.
			stop_y = e.global_position.y - global_position.y
			break
	# All three layers share the same start/end points so they composite
	# as halo-under-beam-under-core. Muzzle just above the ship.
	var points := PackedVector2Array([
		Vector2(0, -10),
		Vector2(0, stop_y),
	])
	if _beam_halo: _beam_halo.points = points
	if _beam_line: _beam_line.points = points
	if _beam_core: _beam_core.points = points


func _sort_by_y_desc(a, b) -> bool:
	return a.global_position.y > b.global_position.y


# Tough/boss detection — scene_file_path string match catches the three
# named bosses; max_hull threshold catches "elite" chaff like bulwark,
# bomber, frigate, etc.
func _is_tough_or_boss(enemy: Node) -> bool:
	if enemy == null:
		return false
	var path: String = enemy.scene_file_path if "scene_file_path" in enemy else ""
	if path.find("boss") != -1:
		return true
	if "max_hull" in enemy and int(enemy.max_hull) > TOUGH_HP_THRESHOLD:
		return true
	if "max_health" in enemy and int(enemy.max_health) > TOUGH_HP_THRESHOLD:
		return true
	return false


func fire_super() -> void:
	# Single-tap super weapon. Needs an equipped DEVICE_BAY Part and at
	# least one charge. Part owns the activation effect (Smart Bomb /
	# Hyper / Drone Swarm / Phase Shift).
	if super_part == null:
		return
	if super_charges <= 0:
		return
	if not is_alive:
		return
	super_charges -= 1
	super_charges_changed.emit(super_charges, max_super_charges)
	# Persist immediately so a mid-combat scene swap (death, level clear)
	# carries the consumed charge forward.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "super_charges" in run:
			run.super_charges = super_charges
	if super_part.has_method("activate"):
		super_part.activate(self)


# Spawn a 4-px white dot at the ship's center so the player can see the
# exact hitbox while focus-dodging. Only visible when focus is held;
# matches Touhou's iconic centered hitbox indicator.
func _update_focus_dot(visible: bool) -> void:
	if _focus_dot == null:
		_focus_dot = Node2D.new()
		_focus_dot.name = "FocusDot"
		var dot := ColorRect.new()
		dot.size = Vector2(4, 4)
		dot.position = Vector2(-2, -2)
		dot.color = Color(1, 1, 1, 0.95)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_dot.add_child(dot)
		_focus_dot.z_index = 100
		add_child(_focus_dot)
	_focus_dot.visible = visible

func _on_gun_cooldown_timeout() -> void:
	can_shoot = true

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemies"):
		area.explode()
		_play_hit_sfx()
		take_damage(2)
	elif area.is_in_group("bullets"):
		_play_hit_sfx()
		take_damage(1)

func _play_hit_sfx() -> void:
	# Alternate between &damage3.wav and &damage9.wav so repeated hits don't
	# stack the exact same waveform.
	if not has_node("BulletHit"):
		return
	var p: AudioStreamPlayer2D = $BulletHit
	p.stream = HIT_SFX_POOL[_hit_sfx_idx]
	_hit_sfx_idx = (_hit_sfx_idx + 1) % HIT_SFX_POOL.size()
	p.pitch_scale = randf_range(0.96, 1.05)
	p.play()


func _on_shield_regen_timer_timeout() -> void:
	if _shield_in_delay:
		# 5s delay just expired — begin 1/sec regen ticks.
		_shield_in_delay = false
		if shield < max_shield:
			$ShieldRegenTimer.wait_time = 1.0
			$ShieldRegenTimer.start()
		return
	# Regen tick: +1 HP per second.
	if shield < max_shield:
		set_shield(shield + 1)


# Read upgrade Mks from /root/Run and translate them into runtime stats.
# Called from start() so every combat scene picks up the latest values.
#   Hull            +1 max hull pip per Mk (base 3)
#   Armor Plating   RETIRED — no-op, kept for save compat
#   Thrusters       +3% speed per Mk
#   Self Repair     +1 hull on sector map return (gates on mk > 0)
#   Shield Capacity +2 max shield HP per Mk (base 10)
#   Shield Recharge RETIRED — regen always 1/sec after 5s delay
func apply_run_upgrades() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Hull: 3 base + 1 per Mk (hull spec 2026-05-26).
	max_hull = 3 + int(run.hull_mk)
	# armor_mk retired — no DR applied (kept in run_state for save compat).
	var speed_pct: float = 1.0 + float(run.thrusters_mk) * 0.03
	speed_multiplier = max(0.3, speed_pct)
	# Shield: 10 base + 2 per Mk (shield spec 2026-05-26).
	max_shield = 10 + int(run.shield_cap_mk) * 2
	# shield_recharge_mk retired — regen is now always 1/sec after 5s delay.


# Self Repair heal moved to sector_map_v3 return (spec 2026-05-26).
# This function is kept as a no-op stub so any lingering call sites don't crash.
func _self_repair_amount() -> int:
	return 0


# ---- Shield ring helpers ----
func _set_shield_ring_alpha(target: float, duration: float) -> void:
	if _shield_mat == null:
		return
	if _shield_alpha_tween and _shield_alpha_tween.is_valid():
		_shield_alpha_tween.kill()
	if duration <= 0.0:
		_shield_mat.set_shader_parameter("alpha", target)
		return
	_shield_alpha_tween = create_tween()
	var current: float = float(_shield_mat.get_shader_parameter("alpha"))
	_shield_alpha_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("alpha", v),
		current, target, duration
	)

func _pulse_shield_ring() -> void:
	if _shield_mat == null:
		return
	if _shield_hit_tween and _shield_hit_tween.is_valid():
		_shield_hit_tween.kill()
	_shield_mat.set_shader_parameter("hit_strength", 1.0)
	_shield_hit_tween = create_tween()
	_shield_hit_tween.tween_method(
		func(v): _shield_mat.set_shader_parameter("hit_strength", v),
		1.0, 0.0, 0.35
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


# Brief on-screen toast announcing the new autofire state. Mounts a
# CanvasLayer above the HUD (layer 20) so it sits over gameplay AND the
# side gutters; auto-frees after ~1s. Stacked invocations replace the
# prior toast rather than piling up.
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
var _autofire_toast: CanvasLayer = null

func _show_autofire_toast(on: bool) -> void:
	if _autofire_toast and is_instance_valid(_autofire_toast):
		_autofire_toast.queue_free()
		_autofire_toast = null
	var layer := CanvasLayer.new()
	layer.layer = 20
	var root := get_tree().root
	if root == null:
		return
	root.add_child(layer)
	_autofire_toast = layer
	var lbl := Label.new()
	lbl.text = "AUTOFIRE: ON" if on else "AUTOFIRE: OFF"
	UiTheme.style_label(lbl, UiTheme.LabelKind.HEADER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	# Drop the label a bit below the top edge so it doesn't clip against
	# the playfield outline. PRESET_CENTER_TOP anchors at y=0; nudge down.
	lbl.position = Vector2(-60, 16)
	lbl.size = Vector2(120, 16)
	layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if _autofire_toast == layer:
			_autofire_toast = null
	)
