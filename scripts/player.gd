extends Area2D

signal shield_changed
signal hull_changed
signal died
# Emitted whenever take_damage() actually applies damage (before shield/hull
# absorption). Lets the HUD react to the magnitude of the hit without having
# to diff old vs new bar values.
signal damaged(amount: int)

# Set to true to make the player immune to all damage (e.g. in Hangar).
var invincible: bool = false

# ---- Stats (mutated by equipped Parts) ----
# Base values; Parts add on top. Gives a sane floor even with no parts equipped.
const ClarityRules = preload("res://scripts/clarity.gd")
# Base move speed = 2 px/frame (120 px/s). Engine parts add ~1 px/f (60 px/s)
# per Mk (caps the build at ~Mk.6 = 8 px/f); effective speed is clamped to the
# 8 px/f readability ceiling at the movement step below. (was flat 100)
var speed: float = 120.0
# Player velocity this frame (px/s). Bullets inherit the component of this
# along their fire direction so the stream keeps constant spacing instead of
# compressing when you fly toward the shots (Doppler). See fire_primary.
var _move_velocity: Vector2 = Vector2.ZERO
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
# the bullet 6px left / right of the player's pixel center each shot.
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
# Burst secondary (Rocket Pod). secondary_mode == BURST routes secondary
# fire through _tick_burst: a trigger fires `secondary_burst_shots` rockets
# one at a time at `secondary_burst_interval` apart (500 RPM = 0.12s),
# alternating the spawn between the -port and +port on X, then locks out
# for `secondary_burst_cooldown` seconds before another cycle can start.
# Set by RocketPodCannon.apply() (Mk-scaled shots + the constants).
var secondary_burst_shots: int = 2
var secondary_burst_interval: float = 0.12
var secondary_burst_cooldown: float = 1.0
var secondary_burst_port_offset: float = 6.0
# Transient burst state machine — runtime only, NOT part of the loadout
# round-trip (the Part writes the stats above; these track the live cycle).
# _burst_phase: 0 = idle/ready, 1 = firing a cycle, 2 = cooling down.
var _burst_phase: int = 0
var _burst_shots_left: int = 0
var _burst_shot_t: float = 0.0
var _burst_cool_t: float = 0.0
var _burst_port_right: bool = false  # toggled each shot; false = -port first
# Secondary ammo (Rocket Pod / Seeking Missile). -1 = unmetered (default
# for Side Pods / Particle Beam / no secondary). >= 0 = counted; 0 =
# empty, silently fails to fire. Seeded by the Part's apply() from
# Run.secondary_ammo so refills survive scene changes.
var secondary_ammo: int = -1
var secondary_ammo_max: int = -1
signal secondary_ammo_changed(value: int, maximum: int)
# Deploy secondary (Combat Drones) — SecondaryMode.DEPLOY. One press spawns a
# timed wave of companion drones, consuming one deploy (secondary_ammo). The
# player owns the live wave: _drones_active gates re-deploy, _deploy_timer
# counts the duration down, _deployed_drones tracks the spawned nodes so we
# can shut them down on expiry. secondary_deploy_duration is written by the
# Combat Drones Part's apply() (Mk-scaled, 8s base). State machine: _tick_deploy.
var secondary_deploy_duration: float = 8.0
var _drones_active: bool = false
var _deploy_timer: float = 0.0
var _deployed_drones: Array = []
# Emitted while a deploy wave is live so the HUD can show a countdown in the
# secondary slot instead of the ammo count. active=false on expiry tells the
# HUD to revert to the ammo number.
signal secondary_timer_changed(seconds: float, active: bool)
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
# (Hyper is a SHIFT_MODE stance now, not a super — its runtime lives below with
# the other Shift-Mode state. See `active_mode` / _tick_hyper_mode.)
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
# I-frames in seconds after a HULL hit. Stops chained instant-kills
# (mine + bomblet) from one-shotting the player through the hull.
const SHIELD_INVULN_SECONDS: float = 0.6
# Short i-frame after a SHIELD-absorbed hit. The shield is an HP POOL now
# (2026-05-26 rework), so a sustained bullet stream SHOULD drain it per
# hit — the old 0.6s full-invuln (carried over from the retired charge
# model) silently dropped any hit landing inside that window, which read
# as "hits on shields don't register sometimes" (Roman). Kept short so a
# multi-pellet cluster (mine + bomblet) entering within ~2 frames is still
# absorbed as one shield event, while normal bullet spacing (> 0.1s)
# registers every hit. Tuning value — Roman can dial this.
const SHIELD_HIT_INVULN_SECONDS: float = 0.1
var _invuln_t: float = 0.0

# Hull: pip-based (3 pips base). Loss is always 1 pip per hit (not damage).
# Hull == 0 → flash pips; next hit fires super-bomb then kills.
# Roman/spec 2026-05-26 rework.
var max_hull: int = 3
var hull: int = 3:
	set = set_hull
# Chance (0.0–1.0) to shrug off a hull hit entirely. 3% per Hull Plating Mk.
var hull_shrug_chance: float = 0.0
var hull_repair_discount: float = 0.0
# armor_mk DR retired. Field kept for save compat.
var hull_damage_reduction: float = 0.0
# Speed multiplier from upgrades (Thrusters). Applied
# in _process so the live speed = base * speed_multiplier.
var speed_multiplier: float = 1.0
# Focus-mode slowdown — held `focus` action drops the ship to FOCUS_FACTOR
# of normal speed for precision dodging. Cave / Touhou convention; ~2/3.
const FOCUS_FACTOR := 0.55
var _focus_dot: Node2D = null
var _focus_was_active: bool = false
var _focus_trail: Line2D = null
var _focus_trail_history: PackedVector2Array = PackedVector2Array()
const FOCUS_TRAIL_LEN := 18
# Focus-mode visual presence: ship goes semi-transparent, gains a soft diffuse
# glow aura, and the engine exhaust doubles in length. (Roman 2026-05-30.)
const FOCUS_SHIP_ALPHA := 0.55                 # ship opacity while focused
const FOCUS_GLOW_COLOR := Color(0.5, 0.9, 1.0) # cool cyan focus aura
const PHASE_GLOW_COLOR := Color(0.2, 0.5, 1.0) # bright blue phase-out aura (no dot/trail)
const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
var _focus_glow: CanvasItem = null
var focus_charge: float = 10.0
var focus_charge_max: float = 10.0
var _focus_regen_delay: float = 0.0
const FOCUS_DRAIN_RATE := 1.0    # seconds of charge lost per second held
const FOCUS_REGEN_RATE := 1.0    # seconds of charge gained per second released
const FOCUS_REGEN_DELAY := 2.0   # seconds after release before regen starts

signal focus_charge_changed(charge: float, max_charge: float)

# Shift-Mode slot (Focus / Phase / Hyper). The equipped ModePart sets `mode_part`
# + `active_mode` in apply(); `active_mode` dispatches the `focus` (Shift) input in
# _process. Default FOCUS so an empty/absent mode slot still behaves as base Focus.
# Mirror of ModePart.Mode — KEEP IN SYNC: 0=FOCUS, 1=PHASE, 2=HYPER.
# Design: docs/shift_mode_system_2026-06-08.md.
enum ShiftMode { FOCUS, PHASE, HYPER }
var active_mode: int = ShiftMode.FOCUS
var mode_part: Resource = null

# --- Hyper mode runtime (active_mode == HYPER) ---
# A Focus-style bar (seconds of uptime). Drains while overdriving, recharges only
# while idle, and can ONLY (re)engage when FULL. While active: primary +fire-rate,
# unlimited primary ammo, +Mk damage. Tunables pulled from the mode part on equip.
var hyper_charge: float = 4.0
var hyper_charge_max: float = 4.0
var _hyper_active: bool = false
var hyper_fire_bonus: float = 0.10
var hyper_damage_mult: float = 1.0
var hyper_recharge_rate: float = 0.8
signal hyper_charge_changed(charge: float, max_charge: float, active: bool)
# Hyper "tell": a pulsing orange outline that speeds up as the bar runs out (Roman 2026-06-10).
var _hyper_outline: Sprite2D = null
var _hyper_pulse_t: float = 0.0
const HYPER_OUTLINE_COLOR := Color(1.0, 0.5, 0.0)   # orange
const HYPER_PULSE_HZ_SLOW: float = 2.0              # pulses/sec at full charge
const HYPER_PULSE_HZ_FAST: float = 9.0             # pulses/sec as it empties

# --- Phase mode runtime (active_mode == PHASE) ---
# Press Shift to phase out: brief intangibility (no incoming damage, no offense),
# consuming one charge. Charges refill by KILLING enemies (on_enemy_killed), not by
# time. Tunables pulled from the mode part on equip.
var phase_charges: int = 2
var phase_charges_max: int = 2
var phase_duration: float = 3.0
var phase_kills_per_charge: int = 4
var _phase_t: float = 0.0
var _phase_kill_count: int = 0
var _phase_glow: CanvasItem = null   # bright-blue diffuse aura while phased
var _phase_was_active: bool = false
# Fading blue after-image ghosts while phased (Roman 2026-06-10).
var _phase_ai_acc: float = 0.0
var _ghost_add_mat: CanvasItemMaterial = null   # shared additive material for all ghosts
const PHASE_AI_INTERVAL: float = 0.06   # seconds between ghosts
const PHASE_AI_LIFETIME: float = 0.34   # ghost fade-out time
signal phase_charges_changed(charges: int, max_charges: int)
# Emitted when the equipped Shift mode changes — the HUD swaps its meter (Focus/
# Hyper bar vs Phase charge readout) on this.
signal mode_changed(active_mode: int)

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

# Autocannon audio — start sound (1.5s spin-up), then regular fire, stop sound on release.
# _ac_spin_t counts up from 0 to AC_SPIN_TIME (1.5s); fire is suppressed until elapsed.
const AC_SPIN_TIME: float = 1.5
var _ac_start_player: AudioStreamPlayer2D = null
var _ac_stop_player: AudioStreamPlayer2D = null
var _ac_spin_t: float = 0.0
var _ac_spinning: bool = false

# Minigun audio — per-shot SFX routed via WeaponSfx (minigun_shoot clips).
# Stop sound plays when firing ends (interruptible — restarting fire cancels it).
var _mg_stop_player: AudioStreamPlayer2D = null
# Minigun hot-path preloads — _fire_minigun_hitscan runs ~20/s; no per-shot load() (review 2026-06-10).
const _MinigunMuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
const _MinigunWeaponSfx = preload("res://scripts/effects/weapon_sfx.gd")
var _mg_stop_pending: bool = false

# Rotary Laser audio — spin-up charge, then a rapid random "pew" per shot while
# firing (replaces the old sustained loop). The fire rate is ~20/s (base_cooldown
# 0.05), so the per-shot SFX is throttled to a sane cadence and the player node
# is polyphonic so the pews overlap cleanly.
const RL_CHARGE_DURATION: float = 0.4
const RL_SHOOT_SFX_MIN_MS: int = 80     # min gap between rotary shoot pews
var _rl_shoot_streams: Array = []
var _rl_shoot_last_ms: int = 0
var _rl_charging: bool = false
var _rl_charged: bool = false
var _rl_charge_t: float = 0.0
var _rl_charge_player: AudioStreamPlayer2D = null
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
	_setup_ac_audio()
	_setup_mg_stop_audio()
	_setup_smoke_trail()
	# Ground shadow on the top parallax layer (Roman, 2026-05-16: ships
	# cast a drop shadow on first-layer parallax objects).
	var ParallaxShadow = load("res://scripts/effects/parallax_shadow.gd")
	ParallaxShadow.attach(self)
	# Oblique drop-shadow under the ship sprite (code-only; no .tscn edits).
	var ShadowFx = load("res://scripts/shadow_fx.gd")
	ShadowFx.attach_shadow($Ship)
	# New ship layers (Roman 2026-06-09 player-art pass): GlowMask = engine glowmask (#00d3ff,
	# fades to half on move-back); Livery = shader-recolored decoration (random per-patrol tint);
	# EngineL/R = engine-trail markers (#00d3ff trails, above the sprites).
	_setup_ship_visuals()
	start()

const ENGINE_GLOW_COLOR := Color(0.0, 0.827, 1.0)   # #00d3ff (engine glowmask + trails)
const PLAYER_TRAIL_DRIFT := 160.0                    # px/s downward exhaust drift (hovering plume)


# Wire up the new ship-art layers (Roman 2026-06-09): engine glowmask tint, the two #00d3ff
# engine trails, and the per-patrol livery recolor.
func _setup_ship_visuals() -> void:
	# Engine glowmask — additive #00d3ff so it reads as emissive. Its alpha is driven in
	# _process (half opacity while moving back).
	if has_node("Ship") and $Ship.has_node("GlowMask"):
		var gm: Sprite2D = $Ship.get_node("GlowMask")
		gm.modulate = ENGINE_GLOW_COLOR
		var gmat := CanvasItemMaterial.new()
		gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gm.material = gmat
	# 1px black outline on the ship body — same outline_fx shader/look the enemies get. Rebuilt on
	# bank since the body is a 3-frame strip (the outline is a single padded frame).
	_rebuild_outline()
	# Engine trails — the SAME style as enemy engines (engine_trail_fx Line2D streak), but in the
	# engine colour (#00d3ff) instead of the enemy yellow.
	# Find every engine marker (any "Engine*" Marker2D): ship A has a single "Engine",
	# ships B/C have "EngineL" + "EngineR" — one trail per marker, no per-variant code.
	var markers: Array = find_children("Engine*", "Marker2D", true, false)
	if not markers.is_empty():
		var EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
		var trail = EngineTrailFx.new()
		add_child(trail)
		# Drift the exhaust downward: the player hovers (the world scrolls past), so without it the
		# trail piles up behind the ship and is invisible. ~160 px/s reads as a steady blue plume.
		trail.setup(self, markers, ENGINE_GLOW_COLOR, PLAYER_TRAIL_DRIFT)
	_apply_livery_color()


var _outline = null
var _outline_frame: int = -1
# (Re)build the body outline for the current bank frame. The padded single-frame texture is cached
# per (texture, frame) in outline_fx, so a rebuild is just a fresh Sprite2D node.
func _rebuild_outline() -> void:
	if not has_node("Ship"):
		return
	if _outline != null and is_instance_valid(_outline):
		_outline.queue_free()
	var OutlineFx = preload("res://scripts/effects/outline_fx.gd")
	_outline = OutlineFx.apply($Ship)
	_outline_frame = $Ship.frame


# Livery recolor: randomize the shader tint per patrol (deterministic off run_seed so it's
# stable within a run); default pure red when there's no run.
func _apply_livery_color() -> void:
	if not (has_node("Ship") and $Ship.has_node("Livery")):
		return
	var lv: Sprite2D = $Ship.get_node("Livery")
	if lv.material == null:
		return
	lv.material = lv.material.duplicate()   # don't mutate the shared scene sub-resource
	var col := Color(1.0, 0.0, 0.0)         # #ff0000 default
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		if run.livery_chosen:
			# Player picked a livery in the ship-select modal — honor it exactly.
			col = run.livery_color
		else:
			# No explicit choice (dev / non-modal entry): deterministic random tint off run_seed.
			var rng := RandomNumberGenerator.new()
			rng.seed = int(run.run_seed)
			col = Color.from_hsv(rng.randf(), rng.randf_range(0.7, 1.0), rng.randf_range(0.85, 1.0))
	lv.material.set_shader_parameter("tint_color", col)


# Bank all three ship layers together — body + livery + glowmask share the 3-frame strip.
func _set_bank_frame(f: int) -> void:
	if not has_node("Ship"):
		return
	$Ship.frame = f
	if $Ship.has_node("Livery"):
		($Ship.get_node("Livery") as Sprite2D).frame = f
	if $Ship.has_node("GlowMask"):
		($Ship.get_node("GlowMask") as Sprite2D).frame = f
	if f != _outline_frame:
		_rebuild_outline()


# Engine glowmask opacity: eases to 0.5 while moving back (down), 1.0 otherwise.
var _engine_glow_a: float = 1.0
func _update_engine_glow(moving_back: bool, delta: float) -> void:
	if not (has_node("Ship") and $Ship.has_node("GlowMask")):
		return
	var target: float = 0.5 if moving_back else 1.0
	_engine_glow_a = move_toward(_engine_glow_a, target, delta * 6.0)
	var gm: Sprite2D = $Ship.get_node("GlowMask")
	gm.modulate.a = _engine_glow_a


# Offset of a scene marker (e.g. "Ship/Muzzle") relative to the player centre, with a fallback
# if the marker is missing. Used so weapons fire from the authored markers, not hardcoded offsets.
func _muzzle_offset(node_path: String, fallback: Vector2) -> Vector2:
	var m: Node = get_node_or_null(node_path)
	if m == null or not (m is Node2D):
		return fallback
	return to_local((m as Node2D).global_position)


# Toggles the wing a single-missile secondary launches from (alternates L/R per shot).
var _secondary_wing: int = 0


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
	var loop_stream: AudioStream = load("res://Sound/weapons/player/Machinegun-Loop-LP.ogg")
	if loop_stream is AudioStreamOggVorbis:
		(loop_stream as AudioStreamOggVorbis).loop = true
	_mg_loop_player = AudioStreamPlayer2D.new()
	_mg_loop_player.name = "MgLoop"
	_mg_loop_player.stream = loop_stream
	_mg_loop_player.volume_db = -3.0
	_mg_loop_player.pitch_scale = 0.92
	_mg_loop_player.bus = "SFX"
	add_child(_mg_loop_player)

	var end_stream: AudioStream = load("res://Sound/weapons/player/Machinegun-End-LP.ogg")
	_mg_end_player = AudioStreamPlayer2D.new()
	_mg_end_player.name = "MgEnd"
	_mg_end_player.stream = end_stream
	_mg_end_player.volume_db = -3.0
	_mg_end_player.pitch_scale = 0.92
	_mg_end_player.bus = "SFX"
	add_child(_mg_end_player)
	# Route the scene-embedded weapon SFX nodes (ShootSound, CannonShoot,
	# Rotary/ParticleBeam, etc.) onto the SFX bus for the Options sound slider.
	var SfxCls = load("res://scripts/effects/sfx.gd")
	SfxCls.route_children_to_sfx(self)
	# Rotary Laser audio nodes come from the player scene.
	_rl_charge_player = get_node_or_null("RotaryLaserCharge")
	_rl_shoot_player_node = get_node_or_null("RotaryLaserShoot")
	_rl_shoot_streams = [
		load("res://Sound/weapons/player/rotary_laser_shoot_1.ogg"),
		load("res://Sound/weapons/player/rotary_laser_shoot_2.ogg"),
		load("res://Sound/weapons/player/rotary_laser_shoot_3.ogg"),
		load("res://Sound/weapons/player/rotary_laser_shoot_4.ogg"),
		load("res://Sound/weapons/player/rotary_laser_shoot_5.ogg"),
		load("res://Sound/weapons/player/rotary_laser_shoot_6.ogg"),
	]
	# Polyphonic so rapid-fire pews overlap instead of cutting each other off.
	if _rl_shoot_player_node:
		_rl_shoot_player_node.max_polyphony = 4
	_pb_charge_player = get_node_or_null("ParticleBeamCharge")
	_pb_loop_player = get_node_or_null("ParticleBeamLoop")
	_pb_stop_player = get_node_or_null("ParticleBeamStop")
	if _pb_loop_player:
		var pls: AudioStream = _pb_loop_player.stream
		if pls is AudioStreamOggVorbis:
			(pls as AudioStreamOggVorbis).loop = true


func _setup_ac_audio() -> void:
	# Autocannon: start sound during spin-up (1.5s), then regular fire,
	# stop sound when firing ends.
	var start_stream: AudioStream = load("res://Sound/weapons/player/autocannon_start.ogg")
	_ac_start_player = AudioStreamPlayer2D.new()
	_ac_start_player.name = "AutocannonStart"
	_ac_start_player.stream = start_stream
	_ac_start_player.volume_db = -3.0
	_ac_start_player.bus = "SFX"
	add_child(_ac_start_player)

	var stop_stream: AudioStream = load("res://Sound/weapons/player/autocannon_stop.ogg")
	_ac_stop_player = AudioStreamPlayer2D.new()
	_ac_stop_player.name = "AutocannonStop"
	_ac_stop_player.stream = stop_stream
	_ac_stop_player.volume_db = -3.0
	_ac_stop_player.bus = "SFX"
	add_child(_ac_stop_player)


func _setup_mg_stop_audio() -> void:
	# Minigun stop sound (plays when firing ends, interruptible if firing resumes).
	var stop_stream: AudioStream = load("res://Sound/weapons/player/minigun_stop.ogg")
	_mg_stop_player = AudioStreamPlayer2D.new()
	_mg_stop_player.name = "MinigunStop"
	_mg_stop_player.stream = stop_stream
	_mg_stop_player.volume_db = -3.0
	_mg_stop_player.bus = "SFX"
	add_child(_mg_stop_player)


func _rl_stop() -> void:
	_rl_charging = false
	_rl_charged = false
	_rl_charge_t = 0.0
	if _rl_charge_player and _rl_charge_player.playing:
		_rl_charge_player.stop()


# One rapid random rotary "pew", throttled so the ~20/s fire rate doesn't spawn a
# voice per shot. Played from the polyphonic RotaryLaserShoot node (SFX bus).
func _play_rotary_shoot_sfx() -> void:
	if _rl_shoot_player_node == null or _rl_shoot_streams.is_empty() or not is_alive:
		return
	var now: int = Time.get_ticks_msec()
	if now - _rl_shoot_last_ms < RL_SHOOT_SFX_MIN_MS:
		return
	_rl_shoot_last_ms = now
	_rl_shoot_player_node.stream = _rl_shoot_streams[randi() % _rl_shoot_streams.size()]
	_rl_shoot_player_node.play()


func stop_all_weapon_audio() -> void:
	if _mg_loop_player and is_instance_valid(_mg_loop_player):
		_mg_loop_player.stop()
	if _ac_start_player and is_instance_valid(_ac_start_player):
		_ac_start_player.stop()
	if _ac_stop_player and is_instance_valid(_ac_stop_player):
		_ac_stop_player.stop()
	if _mg_stop_player and is_instance_valid(_mg_stop_player):
		_mg_stop_player.stop()
	if _rl_charge_player and is_instance_valid(_rl_charge_player):
		_rl_charge_player.stop()
	if _pb_loop_player and is_instance_valid(_pb_loop_player):
		_pb_loop_player.stop()


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
	# Focus charge: always full at combat start.
	focus_charge = focus_charge_max
	_focus_regen_delay = 0.0
	focus_charge_changed.emit(focus_charge, focus_charge_max)
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
	if not controls_enabled:
		# Ship still animates "forward" so it reads as actively flying during
		# the intro slide-in / outro fly-out cinematic.
		_set_bank_frame(1)
		# Stop any in-flight machinegun audio so the loop doesn't keep
		# brrrt'ing while the player is flying off-screen at level end
		# (Roman, 2026-05-16: "make sure to stop them shooting").
		if _mg_firing:
			_mg_firing = false
			if _mg_loop_player and _mg_loop_player.playing:
				_mg_loop_player.stop()
		if _rl_charging or _rl_charged:
			_rl_stop()
		return
	var input := Input.get_vector("left", "right", "up", "down")
	if input.x > 0:
		_set_bank_frame(2)
	elif input.x < 0:
		_set_bank_frame(0)
	else:
		_set_bank_frame(1)
	# Engine glowmask dims to half opacity while moving BACK (down); full bright otherwise.
	_update_engine_glow(input.y > 0.0, delta)
	# Focus mode (Shift, by convention): ⅔-ish speed for precision
	# dodging + show the hitbox dot so the player sees their collider.
	# Charge-gated: focus deactivates when charge hits 0; recharges 2s
	# after release.
	# Focus is one of three Shift modes — only run the Focus stance when it's the
	# active mode. Hyper/Phase handle the same Shift input via their own runtime
	# (_tick_hyper_mode / _tick_phase_mode, below).
	var want_focus: bool = active_mode == ShiftMode.FOCUS and Input.is_action_pressed("focus") and focus_charge > 0.0
	# Drain charge while focused.
	if want_focus:
		focus_charge = max(0.0, focus_charge - FOCUS_DRAIN_RATE * delta)
		_focus_regen_delay = FOCUS_REGEN_DELAY
		focus_charge_changed.emit(focus_charge, focus_charge_max)
	else:
		if _focus_regen_delay > 0.0:
			_focus_regen_delay -= delta
		elif focus_charge < focus_charge_max:
			focus_charge = min(focus_charge_max, focus_charge + FOCUS_REGEN_RATE * delta)
			focus_charge_changed.emit(focus_charge, focus_charge_max)
	# Hyper / Phase share the `focus` (Shift) action — tick their runtime here.
	_tick_hyper_mode(delta)
	_tick_phase_mode(delta)
	var focused: bool = want_focus
	var focus_mult: float = FOCUS_FACTOR if focused else 1.0
	_update_focus_dot(focused)
	# Thrusters / Armor Plating upgrades feed into speed_multiplier;
	# applied here so the runtime stat reflects the live upgrade state.
	# Movement is delta-scaled (framerate-independent). Clamp the step to a
	# 30fps-equivalent ceiling so a frame hitch / huge delta can't teleport the
	# ship across the playfield (matches enemy_core's delta cap). Roman 2026-06-01.
	# Clamp effective speed (engine/wing parts can stack past it) to the 8 px/f
	# readability ceiling so the ship stays controllable; focus slows below it.
	var eff_speed: float = minf(speed * speed_multiplier, ClarityRules.ABS_MAX_SPEED)
	_move_velocity = input * eff_speed * focus_mult
	position += _move_velocity * minf(delta, 1.0 / 30.0)
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
	# Phase mode: while phased out the player is intangible AND cannot hit bullets
	# or enemies — lock off primary offense (secondary is gated below).
	if _phase_t > 0.0:
		fire_held = false
	# Primary Q-cycle retired (2026-06-11 single-active model): the ship carries
	# one active primary; swapping happens at the outpost / ship-manager, sending
	# the old one to the hold. The `primary_swap` action is now unused for cannons.
	if fire_held:
		# EVERY style fires through fire_primary each held frame — it self-gates on
		# GunCooldown/can_shoot, ammo, the rotary charge (not _rl_charged -> no-op), and routes
		# MINIGUN to its hitscan internally. The AUTOCANNON spin-up is the ONLY style whose fire
		# is suppressed up front. (Regression fix 2026-06-10: the weapons rework had folded this
		# call INTO the style branches, so the blaster/heavy/wave/spread/auto-laser/MG/rotary —
		# every style without its own branch-side call — stopped firing entirely.)
		if weapon_style == WS.WeaponStyle.AUTOCANNON:
			if ammo != 0 and is_alive:
				if not _ac_spinning:
					# Start spinning: play start sound and begin the 1.5s delay.
					_ac_spinning = true
					_ac_spin_t = 0.0
					if _ac_start_player and not _ac_start_player.playing:
						_ac_start_player.play()
				else:
					_ac_spin_t += delta
				# Only fire once spin-up is complete.
				if _ac_spin_t >= AC_SPIN_TIME:
					fire_primary()
		else:
			fire_primary()
		# ---- Firing audio/state machines (separate from the fire call) ----
		# Minigun: cancel any pending stop sound — we're still firing.
		if weapon_style == WS.WeaponStyle.MINIGUN:
			_mg_stop_pending = false
		# MG audio loop only when the machinegun is the equipped CANNON
		# AND there's still ammo. Energy blaster fire is silent.
		elif weapon_style == WS.WeaponStyle.MACHINEGUN and ammo != 0 and not _mg_firing and is_alive:
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
	else:
		# Fire released.
		# Autocannon: stop spinning, play stop sound. The reset runs for ANY current style —
		# a Q-swap mid-hold changes weapon_style before release, and gating the reset on
		# AUTOCANNON orphaned _ac_spinning=true (review fix 2026-06-10: re-equipping then
		# skipped the 1.5s spin-up entirely). The stop SOUND still only plays when the
		# autocannon is the active style.
		if _ac_spinning:
			_reset_autocannon_spin()
			if _ac_stop_player and is_alive and weapon_style == WS.WeaponStyle.AUTOCANNON:
				_ac_stop_player.play()
		# Minigun: schedule stop sound to play (will be cancelled if fire resumes).
		# Independent `if` (not elif off the AC reset) so a mid-hold swap still stops cleanly.
		if weapon_style == WS.WeaponStyle.MINIGUN:
			if not _mg_stop_pending and is_alive:
				_mg_stop_pending = true
				if _mg_stop_player and not _mg_stop_player.playing:
					_mg_stop_player.play()
		# Machinegun release: stop loop, play end sound.
		elif _mg_firing:
			_mg_firing = false
			if _mg_loop_player and _mg_loop_player.playing:
				_mg_loop_player.stop()
			if _mg_end_player and is_alive and weapon_style == WS.WeaponStyle.MACHINEGUN:
				_mg_end_player.play()
	if not fire_held and (_rl_charging or _rl_charged):
		_rl_stop()
	# Stop rotary laser loop if ammo runs out while charged.
	if (_rl_charging or _rl_charged) and weapon_style == WS.WeaponStyle.ROTARY_LASER and ammo <= 0:
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
	# Phase mode locks off secondary offense too (still ticks cooldowns via the
	# tick fns; just no fire). DEPLOY keeps ticking its active-wave countdown but
	# won't accept a new deploy press while phased (handled in _tick_deploy).
	var sec_held: bool = Input.is_action_pressed("shoot2") and _phase_t <= 0.0
	if secondary_mode == WS.SecondaryMode.BEAM:
		_tick_beam(sec_held, delta)
	elif secondary_mode == WS.SecondaryMode.BURST:
		_tick_burst(sec_held, delta)
	elif secondary_mode == WS.SecondaryMode.DEPLOY:
		# Runs every frame: ticks the active-wave countdown AND handles the
		# deploy press (gated internally so re-deploy is blocked while live).
		_tick_deploy(delta)
	elif secondary_mode == WS.SecondaryMode.SALVO:
		# Swarm Launcher: press fires a salvo, then a flat cooldown. Gated on
		# the shared _secondary_t cooldown (ticked above) + ammo. Phase-blocked.
		_tick_salvo()
	elif sec_held:
		fire_secondary()
	# Super weapon (X by default, single-tap, consumes a charge). Stub
	# until DEVICE_BAY slot Parts implement themselves.
	if Input.is_action_just_pressed("shoot_nose"):
		fire_super()

# ---- Shift modes (Hyper / Phase) ----------------------------------------
# Focus lives inline in _process; Hyper + Phase share the same `focus` (Shift) action
# but have their own resource models. Design: docs/shift_mode_system_2026-06-08.md.

# Called by ModePart.apply/unapply when the equipped Shift mode changes. Pulls the
# part's Mk-scaled tunables and resets runtime state.
func _on_mode_changed() -> void:
	_hyper_active = false
	_phase_t = 0.0
	mode_changed.emit(active_mode)
	if active_mode == ShiftMode.HYPER and mode_part != null:
		if mode_part.has_method("fire_bonus_at_mark"):
			hyper_fire_bonus = mode_part.fire_bonus_at_mark(int(mode_part.mark))
		if mode_part.has_method("damage_mult_at_mark"):
			hyper_damage_mult = mode_part.damage_mult_at_mark(int(mode_part.mark))
		if "bar_seconds" in mode_part:
			hyper_charge_max = float(mode_part.bar_seconds)
		if "recharge_per_sec" in mode_part:
			hyper_recharge_rate = float(mode_part.recharge_per_sec)
		hyper_charge = hyper_charge_max  # start full / ready
		hyper_charge_changed.emit(hyper_charge, hyper_charge_max, false)
	elif active_mode == ShiftMode.PHASE and mode_part != null:
		if mode_part.has_method("charges_at_mark"):
			phase_charges_max = int(mode_part.charges_at_mark(int(mode_part.mark)))
		if mode_part.has_method("duration_at_mark"):
			phase_duration = float(mode_part.duration_at_mark(int(mode_part.mark)))
		if "kills_per_charge" in mode_part:
			phase_kills_per_charge = int(mode_part.kills_per_charge)
		phase_charges = phase_charges_max  # start full
		_phase_kill_count = 0
		phase_charges_changed.emit(phase_charges, phase_charges_max)
	else:
		# FOCUS (or no mode part) — refresh the focus bar.
		focus_charge_changed.emit(focus_charge, focus_charge_max)


# Hyper: held Shift drains the bar (+fire/ammo/dmg while active); release/empty ends
# it; recharges only while idle; can ONLY (re)engage from a FULL bar (no tapping).
func _tick_hyper_mode(delta: float) -> void:
	if active_mode != ShiftMode.HYPER:
		_clear_hyper_outline()
		return
	var holding: bool = Input.is_action_pressed("focus")
	if _hyper_active:
		hyper_charge = max(0.0, hyper_charge - delta)  # drain 1/s
		if hyper_charge <= 0.0 or not holding:
			_hyper_active = false
		hyper_charge_changed.emit(hyper_charge, hyper_charge_max, _hyper_active)
	else:
		if hyper_charge < hyper_charge_max:
			hyper_charge = min(hyper_charge_max, hyper_charge + hyper_recharge_rate * delta)
			hyper_charge_changed.emit(hyper_charge, hyper_charge_max, false)
		if holding and hyper_charge >= hyper_charge_max:
			_hyper_active = true
			hyper_charge_changed.emit(hyper_charge, hyper_charge_max, true)
	# Pulsing orange outline tell — faster as the bar runs out.
	if _hyper_active:
		_update_hyper_outline(delta)
	else:
		_clear_hyper_outline()


const _OutlineFxCls = preload("res://scripts/effects/outline_fx.gd")

func _update_hyper_outline(delta: float) -> void:
	if _hyper_outline == null or not is_instance_valid(_hyper_outline):
		if not has_node("Ship"):
			return
		_hyper_outline = _OutlineFxCls.apply($Ship, HYPER_OUTLINE_COLOR)
		if _hyper_outline != null:
			_hyper_outline.z_index = -1   # above the black hull outline (-2), below the ship (0)
		_hyper_pulse_t = 0.0
	if _hyper_outline == null or not is_instance_valid(_hyper_outline):
		return
	# Pulse frequency rises from SLOW→FAST as the bar empties.
	var frac: float = 0.0
	if hyper_charge_max > 0.0:
		frac = clampf(1.0 - hyper_charge / hyper_charge_max, 0.0, 1.0)
	var hz: float = lerpf(HYPER_PULSE_HZ_SLOW, HYPER_PULSE_HZ_FAST, frac)
	_hyper_pulse_t += delta * hz
	_hyper_outline.modulate.a = 0.30 + 0.70 * (0.5 + 0.5 * sin(_hyper_pulse_t * TAU))


func _clear_hyper_outline() -> void:
	if _hyper_outline != null and is_instance_valid(_hyper_outline):
		_hyper_outline.queue_free()
	_hyper_outline = null


# Phase: PRESS Shift to phase out — intangible (no incoming damage) + offense locked
# for phase_duration, costs one charge. Charges refill via on_enemy_killed (kills).
func _tick_phase_mode(delta: float) -> void:
	if active_mode != ShiftMode.PHASE:
		_set_phase_glow(false)
		return
	if _phase_t > 0.0:
		_phase_t = max(0.0, _phase_t - delta)
		_invuln_t = max(_invuln_t, _phase_t)  # intangible for the whole window
		# Fading blue after-image ghosts as the ship moves.
		_phase_ai_acc += delta
		if _phase_ai_acc >= PHASE_AI_INTERVAL:
			_phase_ai_acc = 0.0
			_spawn_phase_afterimage()
	if Input.is_action_just_pressed("focus") and _phase_t <= 0.0 and phase_charges > 0:
		phase_charges -= 1
		_phase_t = phase_duration
		_invuln_t = max(_invuln_t, phase_duration)
		_phase_ai_acc = PHASE_AI_INTERVAL  # drop a ghost immediately on entry
		phase_charges_changed.emit(phase_charges, phase_charges_max)
	# Bright-blue diffuse glow while phased (the Phase "tell" — no dot/trail).
	_set_phase_glow(_phase_t > 0.0)


# Spawn a fading blue ghost of the ship body at its current pose. Parented to the combat world (not
# the player) so it stays put while the ship flies on, then fades + frees itself.
func _spawn_phase_afterimage() -> void:
	if not has_node("Ship"):
		return
	var ship := $Ship as Sprite2D
	if ship == null or ship.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = ship.texture
	ghost.hframes = ship.hframes
	ghost.vframes = ship.vframes
	ghost.frame = ship.frame
	ghost.flip_h = ship.flip_h
	ghost.flip_v = ship.flip_v
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.global_position = ship.global_position
	ghost.rotation = global_rotation
	ghost.z_index = -1
	ghost.modulate = Color(PHASE_GLOW_COLOR.r, PHASE_GLOW_COLOR.g, PHASE_GLOW_COLOR.b, 0.55)
	# Shared additive material — ghosts spawn every 0.06s; one cached material serves them all
	# (alpha rides on per-node modulate, so sharing is safe). (Review 2026-06-10.)
	if _ghost_add_mat == null:
		_ghost_add_mat = CanvasItemMaterial.new()
		_ghost_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # glowy blue ghost
	ghost.material = _ghost_add_mat
	var host: Node = get_parent() if get_parent() != null else get_tree().root
	host.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, PHASE_AI_LIFETIME)
	tw.tween_callback(ghost.queue_free)


# Edge-triggered: spawn/free the blue phase aura behind the ship (reuses the
# focus glow shader). Create-once on enter, free on exit — no per-frame churn.
func _set_phase_glow(on: bool) -> void:
	if on == _phase_was_active:
		return
	_phase_was_active = on
	if on:
		if has_node("Ship") and (_phase_glow == null or not is_instance_valid(_phase_glow)):
			_phase_glow = GlowShaderFx.apply($Ship, PHASE_GLOW_COLOR)
	else:
		if _phase_glow != null and is_instance_valid(_phase_glow):
			_phase_glow.queue_free()
		_phase_glow = null


# Phase refills charges by killing enemies. Wired from main._on_enemy_died (the
# bounty-award hook) so only player-caused kills count — off-screen departs don't.
func on_enemy_killed() -> void:
	if active_mode != ShiftMode.PHASE or phase_charges >= phase_charges_max:
		return
	_phase_kill_count += 1
	if _phase_kill_count >= phase_kills_per_charge:
		_phase_kill_count = 0
		phase_charges = min(phase_charges_max, phase_charges + 1)
		phase_charges_changed.emit(phase_charges, phase_charges_max)


# ---- Damage pipeline ----
# Shield is an HP pool — full bullet damage absorbed, no overflow to hull.
# Hull is pip-based — 1 pip per hit when shield is empty.
# Hull == 0 → pips flash; NEXT hit fires super-bomb then kills.
# Spec 2026-05-26 rework.
func take_damage(amount: int) -> void:
	if invincible:
		return
	if not is_alive or amount <= 0:
		return
	# Phase mode: while phased the player absorbs incoming enemy fire instead of taking it —
	# each absorbed hit restores 1 shield point (capped). The bullet that called this still frees
	# itself, so it reads as "absorbed". (Roman 2026-06-10 phase rework.)
	if _phase_t > 0.0:
		if shield < max_shield:
			set_shield(min(max_shield, shield + 1))
			_pulse_shield_ring()
			if has_node("Ship"):
				var HitFlashFx2 = load("res://scripts/effects/hit_flash_fx.gd")
				HitFlashFx2.flash($Ship, HitFlashFx2.FLASH_SHIELD)
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
		# Shield absorbs full hit — no overflow to hull. Short i-frame only,
		# so a sustained bullet stream keeps draining the HP pool per hit.
		set_shield(max(0, shield - amount))
		_invuln_t = SHIELD_HIT_INVULN_SECONDS
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
			# Touhou death-bomb: firing the super on a LETHAL hit must save the
			# player. Don't depend on the part to set _invuln_t — guarantee a
			# survival i-frame here so the charge is never spent for nothing.
			# (Smart Bomb already sets a longer window; max() keeps the longer.)
			_invuln_t = maxf(_invuln_t, SHIELD_INVULN_SECONDS)
			if _invuln_t > 0.0:
				return
		damaged.emit(1)
		set_hull(0)
		die()
		return
	# Normal hull pip loss (hull > 0, shield == 0).
	# Shrug: milestone perk — chance to absorb the hit with no pip loss.
	if hull_shrug_chance > 0.0 and randf() < hull_shrug_chance:
		return
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
	_set_phase_glow(false)  # clean up the Phase aura if we die mid-blink
	_clear_hyper_outline()  # and the Hyper pulse outline
	_hyper_active = false
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
	if _pb_loop_player and is_instance_valid(_pb_loop_player):
		_pb_loop_player.stop()
	$Death.play()

# ---- Fire paths ----
# Primary fire is driven by the CANNON slot Part. Secondary fire will be
# driven by hardpoint/device parts (Phase 2+); for now it's a hook only.
func _is_mg_family(style: int) -> bool:
	# Returns true for Machinegun, Autocannon, and Minigun — weapons that share
	# the orange muzzle flash and smoke+shell eject visuals.
	return style == WS.WeaponStyle.MACHINEGUN or style == WS.WeaponStyle.AUTOCANNON or style == WS.WeaponStyle.MINIGUN


func fire_primary() -> void:
	# Minigun is hitscan, not projectile-based — special handling.
	if weapon_style == WS.WeaponStyle.MINIGUN:
		if not can_shoot:
			return
		if _phase_t > 0.0:
			return  # phased out — no offense
		if _is_replacement_primary_active() and ammo == 0 \
				and not (_hyper_active and active_mode == ShiftMode.HYPER):
			_snap_to_blaster_and_reapply()
			return
		# Minigun: hitscan damage instead of bullet spawn.
		_fire_minigun_hitscan()
		return

	if not can_shoot or bullet_scene == null:
		return
	if _phase_t > 0.0:
		return  # phased out — no offense
	# Metered primary out of ammo. Single-active model (2026-06-11): a REGEN
	# cannon (laser: ammo_recharge_rate > 0) just can't fire until it recharges —
	# it must NOT revert (there's no Q-cycle to get back). A NON-regen cannon
	# (minigun) reverts to an owned blaster. Hyper grants unlimited ammo, so a
	# dry metered weapon keeps firing while Hyper is active.
	if _is_replacement_primary_active() and ammo == 0 \
			and not (_hyper_active and active_mode == ShiftMode.HYPER):
		if ammo_recharge_rate > 0.0:
			return  # regen cannon: pause until it recharges, stay equipped
		_snap_to_blaster_and_reapply()
		return
	# Rotary Laser: also charge-gated.
	if weapon_style == WS.WeaponStyle.ROTARY_LASER and not _rl_charged:
		return
	can_shoot = false
	# Hyper mode: primary fires +hyper_fire_bonus faster (shorter cooldown) while
	# active. start(time) overrides this one cycle without changing wait_time.
	if _hyper_active and active_mode == ShiftMode.HYPER and hyper_fire_bonus > 0.0:
		$GunCooldown.start($GunCooldown.wait_time / (1.0 + hyper_fire_bonus))
	else:
		$GunCooldown.start()
	# Rotary Laser firing sound: a rapid random pew per shot (the old sustained
	# loop's replacement), throttled so the ~20/s fire rate doesn't spam voices.
	if weapon_style == WS.WeaponStyle.ROTARY_LASER:
		_play_rotary_shoot_sfx()
	# Cobalt 2026-05-21 follow-up: emit from the top-center of the player
	# sprite, slightly AHEAD of the ship (above the top edge). Ship is
	# 16×16 centered; top edge sits at local Y=-8, so (-0, -10) is two
	# pixels ahead of the leading edge.
	# Primary fires from the scene's Muzzle marker (Roman 2026-06-09 marker pass).
	var muzzle_off: Vector2 = _muzzle_offset("Ship/Muzzle", Vector2(0, -8))
	var muzzle_pos: Vector2 = global_position + muzzle_off
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
		if b is Node2D:
			(b as Node2D).z_index = -1   # render under the player sprite (Roman 2026-06-09)
		# Propagate the equipped cannon's damage to the bullet so per-Part /
		# per-Mark scaling actually reaches the take_hit call.
		# Hyper mode adds its Mk damage multiplier (even-Mk stacks) while active.
		if "damage" in b:
			var dmg: int = bullet_damage
			if _hyper_active and active_mode == ShiftMode.HYPER:
				dmg = int(round(float(bullet_damage) * hyper_damage_mult))
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
		var spawn_offset: Vector2 = muzzle_off
		if fire_tandem_alternating and count == 1:
			# Auto Laser fires from the wing muzzle markers, alternating L/R.
			var wing: String = "Ship/MuzzleWingL" if _tandem_side == 0 else "Ship/MuzzleWingR"
			var fallback := Vector2(-4.0 if _tandem_side == 0 else 4.0, -2.0)
			spawn_offset = _muzzle_offset(wing, fallback)
			muzzle_pos = global_position + spawn_offset
			_tandem_side = 1 - _tandem_side
		# Doppler fix: add the player's velocity along this bullet's fire
		# direction so flying toward the shots keeps the stream spacing
		# constant instead of bunching it. Forward component only (never
		# negative) so descending fast can't slow/reverse a slow bullet.
		if "speed" in b:
			b.speed += maxf(0.0, _move_velocity.dot(dir))
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
	# Unified player muzzle flash (Roman 2026-06-09): bottom-anchored, ~1 frame, diffuse glow,
	# above the bullets. Colour rules: Auto Laser + Rotary = pure blue; MG family (machinegun,
	# autocannon, minigun) = bright orange; everything else = the engine glow colour.
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	var flash_color: Color = ENGINE_GLOW_COLOR
	if weapon_style == WS.WeaponStyle.ROTARY_LASER or use_rotary_laser_muzzle:
		flash_color = Color(0.2, 0.45, 1.0)        # pure blue
	elif _is_mg_family(weapon_style):
		flash_color = Color(1.0, 0.5, 0.1)         # bright orange (cannon)
	# Autocannon (+ legacy Machinegun) eject the LARGE shell casing; everything else with a shell
	# (none, currently) uses the small one. The Minigun's small shell is on its own hitscan path.
	var _large_shell: bool = weapon_style == WS.WeaponStyle.AUTOCANNON or weapon_style == WS.WeaponStyle.MACHINEGUN
	MuzzleFx.play_player(muzzle_pos, self, flash_color, _is_mg_family(weapon_style), _large_shell)
	# Per-shot cannon SFX. Excluded styles carry their OWN audio elsewhere: MACHINEGUN = the
	# _mg_loop_player loop, MINIGUN = its bespoke _fire_minigun_hitscan call, ROTARY_LASER = the
	# per-shot pew system. AUTOCANNON deliberately falls through here — its autocannon_shoot_*
	# clips play per shot via fire_sfx_kind (review fix 2026-06-10: the old _is_mg_family gate
	# silenced it entirely between the start/stop sounds).
	if weapon_style != WS.WeaponStyle.MACHINEGUN and weapon_style != WS.WeaponStyle.MINIGUN \
			and weapon_style != WS.WeaponStyle.ROTARY_LASER:
		var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
		if WeaponSfx and fire_sfx_kind != WS.FireSfxKind.NONE:
			WeaponSfx.play(get_tree().root, global_position, WS.sfx_kind_string(fire_sfx_kind))
		elif has_node("ShootSound"):
			$ShootSound.play()
	# (Removed the on-fire ship kick-back nudge — Roman 2026-06-09.)
	# Weapons Phase 1: every non-blaster primary deducts ONE ammo per fire.
	# The blaster (cannon_pool[0]) has ammo == -1 and is skipped. When ammo
	# hits 0, snap to the blaster and re-apply on the next frame so the
	# WeaponPart.apply/unapply snapshot cycle happens cleanly outside the
	# fire loop.
	if _is_replacement_primary_active() and ammo > 0 \
			and not (_hyper_active and active_mode == ShiftMode.HYPER):
		# (Hyper mode grants unlimited primary ammo while active — skip decrement.)
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


func _fire_minigun_hitscan() -> void:
	# Minigun hitscan: find the first enemy in the vertical column above the
	# player and damage it. Draws a minigun_tracer sprite as feedback.
	can_shoot = false
	if _hyper_active and active_mode == ShiftMode.HYPER and hyper_fire_bonus > 0.0:
		$GunCooldown.start($GunCooldown.wait_time / (1.0 + hyper_fire_bonus))
	else:
		$GunCooldown.start()

	# Get muzzle position for muzzle flash.
	var muzzle_off: Vector2 = _muzzle_offset("Ship/Muzzle", Vector2(0, -8))
	var muzzle_pos: Vector2 = global_position + muzzle_off

	# Orange muzzle flash + smoke + SMALL shell (Roman 2026-06-10 — minigun uses the small casing,
	# autocannon the large). Const preloads — this runs ~20/s.
	var flash_color: Color = Color(1.0, 0.5, 0.1)  # bright orange
	_MinigunMuzzleFx.play_player(muzzle_pos, self, flash_color, true, false)  # with_smoke_shell, small shell

	# Fire SFX — minigun_shoot clips routed via WeaponSfx.
	_MinigunWeaponSfx.play(get_tree().root, global_position, WS.sfx_kind_string(fire_sfx_kind))

	# Hitscan: the FIRST valid enemy in the vertical column above the player. Single pass
	# (max-by-Y, no array+sort — 20 shots/sec hot path). Skips dying / recycling /
	# fully-offscreen enemies: the take_hit guard makes those immune, so targeting them would
	# let an untargetable parallax fly-back ghost absorb the column while live enemies behind
	# it go unhit (review fix 2026-06-10).
	# Column WIDTH (Roman 2026-06-10): a 6px half-width almost never lined up with a streaming
	# enemy, so the gun read as "no damage". ~enemy-width column makes the bullet-hose usable.
	const HITSCAN_HALF_WIDTH: float = 11.0  # pixels from player center to column edge
	var tree := get_tree()
	if tree != null:
		var target: Node2D = null
		var best_y: float = -INF
		for e in tree.get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or not (e is Node2D):
				continue
			# Skip enemies below the player or outside the column.
			if e.global_position.y > global_position.y:
				continue
			if absf(e.global_position.x - global_position.x) > HITSCAN_HALF_WIDTH:
				continue
			# Skip untargetable enemies (mirrors enemy_base.take_hit's immunity guard).
			if e.get("_dying") == true:
				continue
			if e.has_method("is_recycling") and e.is_recycling():
				continue
			if e.has_method("is_fully_offscreen") and e.is_fully_offscreen():
				continue
			if e.global_position.y > best_y:
				best_y = e.global_position.y
				target = e

		# Beam end: the hit point if we found a target, else straight up off the top of the screen.
		# The bullet-stream tracer ALWAYS draws (Roman 2026-06-10: "no bullet stream effect" — it used
		# to only draw on a hit, so between hits nothing showed).
		var beam_end_y: float = best_y if target != null else -8.0
		_draw_minigun_tracer(muzzle_pos, Vector2(muzzle_pos.x, beam_end_y))
		if target != null and target.has_method("take_hit"):
			var dmg: int = bullet_damage
			if _hyper_active and active_mode == ShiftMode.HYPER:
				dmg = int(round(float(bullet_damage) * hyper_damage_mult))
			target.take_hit(dmg)

	# Deduct ammo.
	if _is_replacement_primary_active() and ammo > 0 \
			and not (_hyper_active and active_mode == ShiftMode.HYPER):
		ammo -= 1
		ammo_changed.emit(ammo)
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			run.ammo = ammo
			var active = run.get_active_cannon()
			if active != null and "current_ammo" in active:
				active.current_ammo = ammo
		if ammo == 0:
			call_deferred("_snap_to_blaster_and_reapply")


const _MINIGUN_TRACER_TEX = preload("res://graphics/projectiles/minigun_tracer.png")

func _draw_minigun_tracer(from_pos: Vector2, to_pos: Vector2) -> void:
	# The "beam of bullets" (Roman): the minigun_tracer (3×8) tiled VERTICALLY up the column as
	# distinct 8px-tall bullets. A REGION-tiled Sprite2D keeps the sprite UPRIGHT — a Line2D maps the
	# texture's width along the beam and would squish the 8px height across the 3px width. The region
	# is the full beam length and the texture repeats to fill it, so the 8px frame is the tile period.
	# The beam is vertical (the caller passes a straight-up endpoint). Fresh fading beam per shot
	# (~20/s) reads as a continuous stream.
	var top_y: float = minf(from_pos.y, to_pos.y)
	var length: float = absf(from_pos.y - to_pos.y)
	if length < 1.0:
		return
	var beam := Sprite2D.new()
	beam.texture = _MINIGUN_TRACER_TEX
	beam.centered = false
	beam.region_enabled = true
	beam.region_rect = Rect2(0.0, 0.0, 3.0, length)   # 3px wide × full length; texture tiles to fill it
	beam.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # required for the region to TILE (not clamp)
	beam.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels
	beam.position = Vector2(from_pos.x - 1.5, top_y)  # 3px wide, centred on the column x
	beam.z_index = 2
	beam.z_as_relative = false
	var parent: Node = get_parent() if get_parent() != null else get_tree().root
	parent.add_child(beam)
	# Fade and disappear quickly.
	var tw := beam.create_tween()
	tw.tween_property(beam, "modulate:a", 0.0, 0.07)
	tw.tween_callback(beam.queue_free)


# True when the active primary is a METERED cannon (carries ammo). Infinite
# blasters (Energy/Heavy/Twin) seed ammo_max = -1. Single-active model
# (2026-06-11): the discriminator is "does it meter ammo", not the pool index.
func _is_replacement_primary_active() -> bool:
	return ammo_max > 0


# Snap the active cannon back to cannon_pool[0] (blaster) and re-apply it
# through the loadout system so bullet_scene / cooldown / damage / SFX all
# revert. Called when ammo hits 0 OR when the player presses primary_swap.
func _snap_to_blaster_and_reapply() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Single-active model: pull an owned blaster out of the hold (the dry cannon
	# goes to the hold, refillable later). No permanent slot-0 blaster anymore.
	run.revert_to_blaster()
	_reapply_active_cannon()


# Clear the Autocannon spin-up state (flag + timer + start sound). Called on fire-release and on
# every cannon re-apply (Q-swap / ammo-empty blaster snap) so a mid-hold weapon change can never
# orphan _ac_spinning=true and let a later re-equip skip the 1.5s spin-up (review fix 2026-06-10).
func _reset_autocannon_spin() -> void:
	_ac_spinning = false
	_ac_spin_t = 0.0
	if _ac_start_player and is_instance_valid(_ac_start_player) and _ac_start_player.playing:
		_ac_start_player.stop()


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
	# The cannon (and thus weapon_style) is about to change — drop any in-flight spin-up.
	_reset_autocannon_spin()
	const Slots = preload("res://scripts/weapons/SlotTypes.gd")
	loadout.equip(Slots.SlotType.CANNON, active)


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
		# Single-missile secondaries (seeker / anti-ship) launch from the wing markers,
		# alternating L/R. Multi-pod (Side Pods) keep their fanned offsets.
		if count == 1:
			var wing: String = "Ship/LaunchWingL" if _secondary_wing == 0 else "Ship/LaunchWingR"
			var fallback := Vector2(-6.0 if _secondary_wing == 0 else 6.0, 1.0)
			b.start(position + _muzzle_offset(wing, fallback))
			_secondary_wing = 1 - _secondary_wing
		else:
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


## Burst Rocket Pod ##

# Burst-fire state machine for the Rocket Pod (secondary_mode == BURST).
# Driven every frame with whether shoot2 is held.
#   phase 0 (idle): a held trigger starts a cycle if not empty on ammo.
#   phase 1 (firing): loose one rocket every secondary_burst_interval,
#                     alternating -port / +port, until the cycle's shots
#                     are spent, then enter cooldown.
#   phase 2 (cooling): wait secondary_burst_cooldown, then return to idle.
# Autofire (held trigger) automatically starts the next cycle once the
# cooldown clears. Ammo is charged per rocket (one round per rocket).
func _tick_burst(held: bool, delta: float) -> void:
	if not is_alive:
		return
	match _burst_phase:
		1:  # firing the current cycle
			_burst_shot_t -= delta
			while _burst_phase == 1 and _burst_shot_t <= 0.0 and _burst_shots_left > 0:
				# Out of ammo mid-cycle: stop and cool down.
				if secondary_ammo == 0:
					_burst_shots_left = 0
					break
				_spawn_burst_rocket()
				_burst_shots_left -= 1
				_burst_shot_t += secondary_burst_interval
			if _burst_shots_left <= 0:
				_burst_phase = 2
				_burst_cool_t = secondary_burst_cooldown
		2:  # cooldown lockout
			_burst_cool_t -= delta
			if _burst_cool_t <= 0.0:
				_burst_phase = 0
		_:  # idle / ready
			if held and secondary_bullet_scene != null and secondary_ammo != 0:
				_burst_phase = 1
				_burst_shots_left = max(1, secondary_burst_shots)
				_burst_shot_t = 0.0
				_burst_port_right = false  # first rocket from the -port


# Spawn one rocket from the alternating wing port, charge one round of
# ammo, and play the rocket SFX. Mirrors fire_secondary's spawn/ammo path
# but for a single rocket at the toggled X offset.
func _spawn_burst_rocket() -> void:
	if secondary_bullet_scene == null:
		return
	# Rocket Pod launches from the alternating wing markers.
	var wing: String = "Ship/LaunchWingR" if _burst_port_right else "Ship/LaunchWingL"
	var fallback := Vector2(secondary_burst_port_offset if _burst_port_right else -secondary_burst_port_offset, 0.0)
	_burst_port_right = not _burst_port_right
	var b: Node = secondary_bullet_scene.instantiate()
	_bullet_parent().add_child(b)
	if "damage_on_contact" in b:
		b.damage_on_contact = secondary_damage
	if "damage" in b:
		b.damage = secondary_damage
	b.start(position + _muzzle_offset(wing, fallback))
	var WeaponSfxBurst = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfxBurst:
		WeaponSfxBurst.play(get_tree().root, global_position, "rocket")
	# One round per rocket (per-rocket ammo cost).
	if secondary_ammo > 0:
		secondary_ammo -= 1
		secondary_ammo_changed.emit(secondary_ammo, secondary_ammo_max)
		if has_node("/root/Run"):
			get_node("/root/Run").secondary_ammo = secondary_ammo


## Deployable Drones (Combat Drones) ##

# Deploy-secondary state machine (secondary_mode == DEPLOY). Driven every
# frame. A press (shoot2, edge) spawns a timed wave of companion drones via
# the equipped secondary Part's deploy(); the wave is live for
# secondary_deploy_duration seconds, during which:
#   - re-deploy is blocked (_drones_active gate),
#   - the remaining time is pushed to the HUD via secondary_timer_changed.
# On expiry the surviving drones are told to shut down (darken + fall away),
# and the HUD reverts to the deploy-ammo count.
func _tick_deploy(delta: float) -> void:
	if not is_alive:
		return
	if _drones_active:
		_deploy_timer -= delta
		# Prune freed drones from the tracking list (early MAX_HITS deaths).
		for i in range(_deployed_drones.size() - 1, -1, -1):
			if not is_instance_valid(_deployed_drones[i]):
				_deployed_drones.remove_at(i)
		if _deploy_timer <= 0.0:
			_end_deploy()
		else:
			secondary_timer_changed.emit(_deploy_timer, true)
		return
	# Idle — wait for a deploy press. Ammo-gated (0 = empty).
	if not Input.is_action_just_pressed("shoot2"):
		return
	if secondary_ammo == 0:
		return
	var part = _secondary_part()
	if part == null or not part.has_method("deploy"):
		return
	var spawned: Array = part.deploy(self)
	if spawned.is_empty():
		return
	_deployed_drones = spawned
	_drones_active = true
	# Duration: prefer the live Part value (Mk-scaled) over the cached field.
	var dur: float = secondary_deploy_duration
	if part.has_method("deploy_duration"):
		dur = float(part.deploy_duration())
	_deploy_timer = dur
	secondary_timer_changed.emit(_deploy_timer, true)
	# Consume one deploy.
	if secondary_ammo > 0:
		secondary_ammo -= 1
		secondary_ammo_changed.emit(secondary_ammo, secondary_ammo_max)
		if has_node("/root/Run"):
			get_node("/root/Run").secondary_ammo = secondary_ammo


# End an active deploy wave: shut down (darken + fall) any surviving drones,
# clear the gate, and tell the HUD to revert to the ammo count.
func _end_deploy() -> void:
	for d in _deployed_drones:
		if is_instance_valid(d) and d.has_method("begin_shutdown"):
			d.begin_shutdown()
		elif is_instance_valid(d):
			d.queue_free()
	_deployed_drones.clear()
	_drones_active = false
	_deploy_timer = 0.0
	secondary_timer_changed.emit(0.0, false)


# Swarm Launcher (SecondaryMode.SALVO): one press fires a fire-and-forget salvo of
# homing missiles, consumes one ammo, then a flat cooldown before the next. Gated on
# the shared _secondary_t cooldown (ticked toward secondary_cooldown every frame) +
# ammo. Phase-locked (no offense while phased). The Part's fire_salvo() owns the
# spawn + distinct-target assignment; the missiles are fire-and-forget (not tracked).
func _tick_salvo() -> void:
	if not is_alive or _phase_t > 0.0:
		return
	if not Input.is_action_just_pressed("shoot2"):
		return
	if secondary_ammo == 0:
		return
	if _secondary_t < secondary_cooldown:
		return  # still cooling down
	var part = _secondary_part()
	if part == null or not part.has_method("fire_salvo"):
		return
	if not part.fire_salvo(self):
		return
	_secondary_t = 0.0  # restart the cooldown
	if secondary_ammo > 0:
		secondary_ammo -= 1
		secondary_ammo_changed.emit(secondary_ammo, secondary_ammo_max)
		if has_node("/root/Run"):
			get_node("/root/Run").secondary_ammo = secondary_ammo


# Resolve the equipped secondary Part (HARDPOINT_WING) so DEPLOY can call
# deploy() on it. Prefers the player's live loadout node (the part instance
# whose apply() set up this secondary); falls back to Run.loadout_snapshot.
func _secondary_part():
	var SlotsP = preload("res://scripts/weapons/SlotTypes.gd")
	if loadout != null and loadout.has_method("get_part"):
		var p = loadout.get_part(SlotsP.SlotType.HARDPOINT_WING)
		if p != null:
			return p
	if not has_node("/root/Run"):
		return null
	var run = get_node("/root/Run")
	if not ("loadout_snapshot" in run) or not (run.loadout_snapshot is Dictionary):
		return null
	return run.loadout_snapshot.get(SlotsP.SlotType.HARDPOINT_WING, null)


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
	s.position = _muzzle_offset("Ship/Muzzle", Vector2(0, -8))  # the muzzle marker
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
		# Safety net: the _tick_beam_flash call above can complete a WARMUP→HOLD
		# transition on the very frame we release, starting _pb_loop_player (1501)
		# before _beam_active is ever set — so the _beam_active stop above would
		# miss it and the loop SFX would play indefinitely. Guarantee it's stopped
		# on any release.
		if _pb_loop_player and _pb_loop_player.playing:
			_pb_loop_player.stop()
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
	# Edge-triggered sound + glow aura + doubled exhaust. Create-once on enter,
	# free/restore on exit — no per-frame node churn.
	if visible and not _focus_was_active:
		_play_focus_sound(true)
		_focus_visuals_enter()
	elif not visible and _focus_was_active:
		_play_focus_sound(false)
		_focus_visuals_exit()
	_focus_was_active = visible
	# Blue tint + semi-transparency while focused. Per-frame is idempotent and
	# harmless; the modulate alpha now actually renders because hit_flash.gdshader
	# multiplies by the built-in COLOR (it previously clobbered modulate alpha,
	# which is why focus transparency regressed once the ship took its first hit).
	if has_node("Ship"):
		if visible:
			$Ship.modulate = Color(0.5, 0.7, 1.0, FOCUS_SHIP_ALPHA)
		else:
			$Ship.modulate = Color(1.0, 1.0, 1.0, 1.0)
	# Trail management — Line2D parented to get_parent() so it stays in world space.
	if visible:
		if _focus_trail == null or not is_instance_valid(_focus_trail):
			_focus_trail = Line2D.new()
			_focus_trail.width = 2.0
			_focus_trail.joint_mode = Line2D.LINE_JOINT_ROUND
			_focus_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
			_focus_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
			_focus_trail.z_index = 99
			var grad := Gradient.new()
			grad.set_color(0, Color(0.4, 0.7, 1.0, 0.0))
			grad.set_color(1, Color(0.4, 0.7, 1.0, 0.8))
			_focus_trail.gradient = grad
			get_parent().add_child(_focus_trail)
			_focus_trail_history.clear()
		_focus_trail_history.append(global_position)
		if _focus_trail_history.size() > FOCUS_TRAIL_LEN:
			_focus_trail_history = _focus_trail_history.slice(_focus_trail_history.size() - FOCUS_TRAIL_LEN)
		var local_pts := PackedVector2Array()
		for gp in _focus_trail_history:
			local_pts.append(get_parent().to_local(gp))
		_focus_trail.points = local_pts
	else:
		if _focus_trail != null and is_instance_valid(_focus_trail):
			_focus_trail.queue_free()
			_focus_trail = null
		_focus_trail_history.clear()


# Focus-enter: spawn the diffuse glow aura behind the ship sprite and double
# the engine exhaust length. Guarded against double-spawn so a stray re-entry
# never leaks a second glow node.
func _focus_visuals_enter() -> void:
	if not has_node("Ship"):
		return
	# Soft cyan bloom behind the ship (GlowShaderFx parents a halo quad as a
	# sibling at z_index -1). apply() returns a typed CanvasItem.
	if _focus_glow == null or not is_instance_valid(_focus_glow):
		_focus_glow = GlowShaderFx.apply($Ship, FOCUS_GLOW_COLOR)


# Focus-exit: free the glow aura.
func _focus_visuals_exit() -> void:
	if _focus_glow != null and is_instance_valid(_focus_glow):
		_focus_glow.queue_free()
	_focus_glow = null


func _play_focus_sound(_starting: bool) -> void:
	pass  # TODO: swap in focus_start.wav / focus_end.wav when assets land

func _on_gun_cooldown_timeout() -> void:
	can_shoot = true

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemies"):
		if area.has_method("take_hit"):
			area.take_hit(6)
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
#   Hull            base 2 + min(Mk,8) pips; Mk.9 perk = hull repair -30%
#   Armor Plating   RETIRED — no-op, kept for save compat
#   Thrusters       +3% speed per Mk
#   Self Repair     +1 hull on sector map return (gates on mk > 0)
#   Shield Capacity +2 max shield HP per Mk (base 10)
#   Shield Recharge RETIRED — regen always 1/sec after 5s delay
func apply_run_upgrades() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Hull: 2 base + min(Mk, 8) → Mk.1=3, Mk.8=10, Mk.9=10 (Mk.9 perk is repair discount).
	max_hull = 2 + min(int(run.hull_mk), 8)
	hull_repair_discount = 0.30 if run.hull_mk >= 9 else 0.0
	# Shrug chance: 3% per Hull Plating Mk (Mk.1–8) + 6% bonus at Mk.9 → 30% total at Mk.9.
	hull_shrug_chance = 0.03 * min(run.hull_plating_mk, 8) + (0.06 if run.hull_plating_mk >= 9 else 0.0)
	# armor_mk retired — no DR applied (kept in run_state for save compat).
	var speed_pct: float = 1.0 + float(run.thrusters_mk) * 0.03
	speed_multiplier = max(0.3, speed_pct)
	# Shield: 10 base + 2 per Mk + 2 bonus at Mk.9 → Mk.1=12, Mk.8=26, Mk.9=30.
	var _shield_bonus := 2 if run.shield_cap_mk >= 9 else 0
	max_shield = 10 + int(run.shield_cap_mk) * 2 + _shield_bonus
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
