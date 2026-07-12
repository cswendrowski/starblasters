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
const ClarityRules = preload("res://scripts/systems/clarity.gd")
# Base move speed = 2 px/frame (120 px/s). Engine parts add ~1 px/f (60 px/s)
# per Mk (caps the build at ~Mk.6 = 8 px/f); effective speed is clamped to the
# 8 px/f readability ceiling at the movement step below. (was flat 100)
var speed: float = 120.0
# Player velocity this frame (px/s). Bullets inherit the component of this
# along their fire direction so the stream keeps constant spacing instead of
# compressing when you fly toward the shots (Doppler). See fire_primary.
var _move_velocity: Vector2 = Vector2.ZERO
# Ram-enemy knockback (Roman 2026-07-06): an asteroid-style billiards shove on contact with a `ram` enemy.
const RAM_KICK := 34.0            # px shoved away from the ram enemy (asteroid PLAYER_KICK is 25)
const RAM_KICK_GRACE_MS := 400    # min ms between shoves so a ram can't pinball the player
var _last_ram_kick_ms: int = 0
var cooldown: float = 0.15
var bullet_damage: int = 1
# Spread fire knobs — used by the Spread Cannon Part. Default 1 bullet
# straight forward (legacy behavior). Spread Cannon's apply() sets
# bullet_spread_count > 1 + bullet_spread_degrees > 0.
var bullet_spread_count: int = 1
var bullet_spread_degrees: float = 0.0
# When true, the spread fan fires each bullet at a RANDOM angle within the cone (a real
# shotgun) instead of evenly spaced. Shredder sets this; Scatter Blaster leaves it false.
var bullet_spread_random: bool = false
# Pulse Laser (PULSE_LASER weapon_style, Roman 2026-06-11): a 1px HITSCAN beam from the
# nose that stays pinpoint for `pulse_accuracy_window` shots, then accrues +1° dispersion
# per shot (cap PULSE_MAX_DISPERSION), decaying when idle. The beam tints white→blue as
# it grows. The Part stamps pulse_accuracy_window per Mk (base 10, +2/Mk).
var pulse_accuracy_window: int = 10
var _pulse_dispersion: float = 0.0       # current cone WIDTH in degrees
var _pulse_shot_count: int = 0           # shots fired in the current sustained burst
const PULSE_MAX_DISPERSION: float = 20.0
const PULSE_DISPERSION_DECAY: float = 2.0       # deg/sec recovered when not firing
const PULSE_RANGE: float = 320.0                # beam reach (px)
const PULSE_HIT_TOLERANCE: float = 7.0          # perpendicular px the 1px beam still hits
const PULSE_INACCURATE_COLOR := Color(0.0, 0.06, 0.847)  # #000fd8 — fully-dispersed hue
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
# Twin Blaster: alternate the primary muzzle X by ±this many px each shot (woven
# twin stream). 0 = off. Distinct from fire_tandem_alternating (wing markers) —
# this offsets the single Cannon marker laterally instead.
var primary_lateral_alternate: float = 0.0
# Quad Lasers: when non-empty, the primary fires one bolt per offset, all PARALLEL
# (straight up) at muzzle + offset (Vector2, so outer bolts can sit lower). Overrides
# the spread fan + tandem/lateral.
var primary_parallel_offsets: PackedVector2Array = PackedVector2Array()
# Use the rotary laser muzzle FX in place of the default energy muzzle.
# Set by cannons (Auto Laser) that want the rotary laser flash without
# being on the ROTARY_LASER ammo/charge path.
var use_rotary_laser_muzzle: bool = false
# Set by the Shredder so it gets the autocannon muzzle look (orange flash + smoke +
# small shell casing) despite firing on the ENERGY/spread path (Roman 2026-06-11).
var use_autocannon_muzzle: bool = false
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
# (Hyper is a SHIFT_MODE stance now, not a super — it rides the unified Shift-mode
# runtime below. See `active_mode` / _tick_shift_mode.)
# Exported so player.tscn can assign a fallback bullet; parts override at runtime.
@export var bullet_scene: PackedScene
@export var super_scene: PackedScene
@export var heavy_scene: PackedScene
@export var chain_scene: PackedScene

# Pool of hit-flinch SFX rotated each time the player takes a hit. Two
# variants keep the sound from feeling samey under sustained fire.
const HIT_SFX_POOL: Array = [
	preload("res://assets/audio/SFX_hit&damage3.wav"),
	preload("res://assets/audio/SFX_hit&damage9.wav"),
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

# Hull: pip-based. Loss is always 1 pip per hit (not damage). BASE hull is 2 pips —
# apply_run_upgrades() sets max_hull = 2 + Reinforced Hull module pips; the `= 3` defaults
# below are pre-upgrade placeholders, overwritten before combat. (Base 2 is intentional:
# De-Limiter peaks after one pip lost and the 2nd damage-tell at 0.78 lost-hull never fires
# until Reinforced Hull deepens the bar. Health audit 2026-06-15.)
# Hull == 0 → flash pips; next hit fires super-bomb then kills.
# Roman/spec 2026-05-26 rework.
var max_hull: int = 3
var hull: int = 3:
	set = set_hull
# Chance (0.0–1.0) to shrug off a hull hit entirely. 3% per Hull Plating Mk.
var hull_shrug_chance: float = 0.0
# armor_mk DR retired. Field kept for save compat.
var hull_damage_reduction: float = 0.0
# Speed multiplier from upgrades (Thrusters). Applied
# in _process so the live speed = base * speed_multiplier.
var speed_multiplier: float = 1.0
var _focus_dot: Node2D = null
# Real 1px central collision swapped in while focused (the main hitbox is disabled).
var _focus_hitbox: CollisionShape2D = null
# Bright teal = the shield color (hex_shield.gdshader) — for the focus dot + trail.
const FOCUS_DOT_COLOR := Color(0.35, 0.85, 1.0, 1.0)
var _focus_was_active: bool = false
var _focus_trail: Line2D = null
var _focus_trail_history: PackedVector2Array = PackedVector2Array()
const FOCUS_TRAIL_LEN := 36   # long trail, ample segments (Roman 2026-06-11)
# Focus-mode visual presence: ship goes semi-transparent, gains a soft diffuse
# glow aura, and the engine exhaust doubles in length. (Roman 2026-05-30.)
const FOCUS_SHIP_ALPHA := 0.55                 # ship opacity while focused
const FOCUS_GLOW_COLOR := Color(0.5, 0.9, 1.0) # cool cyan focus aura
const PHASE_GLOW_COLOR := Color(0.2, 0.5, 1.0) # bright blue phase-out aura (no dot/trail)
const GlowFx = preload("res://scripts/effects/glow_fx.gd")
var _focus_glow: CanvasItem = null
# Focus's resource is now the unified Shift-mode system below (mode_charges /
# mode_active_t / mode_duration). The old FOCUS_FACTOR speed cut is retired — Focus no
# longer slows the ship (speed is only touched by Rush).

# Shift-Mode slot (Focus / Phase / Hyper). The equipped ModePart sets `mode_part`
# + `active_mode` in apply(); `active_mode` selects WHICH effect the unified runtime
# dispatches. Default FOCUS so an empty/absent mode slot still behaves as base Focus.
# Mirror of ModePart.Mode — KEEP IN SYNC: 0=FOCUS, 1=PHASE, 2=HYPER.
# Design: docs/shift_mode_system_2026-06-08.md.
enum ShiftMode { FOCUS, PHASE, HYPER, RUSH, REFIRE, ECHO, THIEF, REFLECT }
var active_mode: int = ShiftMode.FOCUS
var mode_part: Resource = null

# --- Unified Shift-mode runtime (the singular system; _tick_shift_mode) ---
# Press Shift → spend one charge → active for `mode_duration` seconds → charges refill
# per `mode_regen_kind` (TIME secs/charge while idle, or KILLS via on_enemy_killed). The
# per-mode EFFECT is dispatched on `active_mode` (Focus slow / Phase intangible / Hyper
# overdrive). Params + effect tunables are pulled from the equipped part in
# _on_mode_changed. Mirror of ModePart.ModeRegen — KEEP IN SYNC: 0=TIME, 1=KILLS.
enum ModeRegen { TIME, KILLS }
var mode_charges: int = 3
var mode_charges_max: int = 3
var mode_active_t: float = 0.0          # remaining active seconds (0 = inactive)
var mode_duration: float = 3.0          # full activation length (duration bar denominator)
var mode_regen_kind: int = ModeRegen.TIME
var mode_regen_secs: float = 3.0        # TIME: seconds per +1 charge
var mode_kills_per_charge: int = 4      # KILLS: kills per +1 charge
var _mode_regen_acc: float = 0.0        # time / kill accumulator toward the next charge
# Pips (discrete charges) + duration bar. mode_changed swaps the HUD meter's mode.
signal mode_charges_changed(charges: int, max_charges: int)
signal mode_duration_changed(active_t: float, duration: float)
signal mode_changed(active_mode: int)

func mode_is_active() -> bool:
	return mode_active_t > 0.0

# Per-mode effect gates — "the active mode is X and currently running". Read by the
# scattered fire / damage / ammo / visual paths so a mode's effect only applies while live.
func _focus_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.FOCUS
func _phase_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.PHASE
func _hyper_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.HYPER
func _rush_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.RUSH
func _refire_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.REFIRE
func _echo_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.ECHO
func _thief_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.THIEF
func _reflect_on() -> bool:
	return mode_active_t > 0.0 and active_mode == ShiftMode.REFLECT

# Per-mode effect tunables, pulled from the equipped part in _on_mode_changed (only the
# active mode's value is meaningful at a time). Magnitudes are first-pass placeholders.
var focus_crit_chance: float = 0.15    # Focus: +crit chance while active (stacks w/ module)
var rush_speed_bonus: float = 0.25     # Rush: +move-speed fraction while active
var refire_fire_bonus: float = 0.30    # Refire: +fire-rate fraction while active (pays ammo)
var reflect_chance: float = 0.35       # Reflect: per-hit chance an incoming shot bounces back
var thief_regen_per_hit: int = 1       # Thief: shield restored per caught bullet
var thief_catch_radius: float = 40.0   # Thief: bubble radius (px) that grabs enemy bullets
var echo_delay: float = 0.35           # Echo: ghost trails the player by this many seconds
# Hyper "tell": a pulsing orange outline that speeds up as the window runs out.
var _hyper_outline: Sprite2D = null
var _hyper_pulse_t: float = 0.0
const HYPER_OUTLINE_COLOR := Color(1.0, 0.5, 0.0)   # orange
const HYPER_PULSE_HZ_SLOW: float = 2.0              # pulses/sec at activation
const HYPER_PULSE_HZ_FAST: float = 9.0             # pulses/sec as it empties

# Phase effect visuals (intangibility itself is just "while active").
var _phase_glow: CanvasItem = null   # bright-blue diffuse aura while phased
var _phase_was_active: bool = false
# Fading blue after-image ghosts while phased (Roman 2026-06-10).
var _phase_ai_acc: float = 0.0
var _ghost_add_mat: CanvasItemMaterial = null   # shared additive material for all ghosts
const PHASE_AI_INTERVAL: float = 0.06   # seconds between ghosts
const PHASE_AI_LIFETIME: float = 0.34   # ghost fade-out time

# Mode field: a bullet-detecting Area2D shared by Thief (steals → shield) and Reflect
# (bounces a fraction back at enemies). Slightly larger than the ship so it intercepts
# bullets before the player hurtbox. Thief also shows a purple hex-sphere visual.
var _mode_field: Area2D = null
var _thief_sphere: ColorRect = null
var _thief_mat: ShaderMaterial = null
const THIEF_SPHERE_COLOR := Color(0.72, 0.32, 1.0)   # purple
const REFLECT_FIELD_RADIUS := 20.0                   # Reflect intercept radius (px)
# Echo effect: a delayed ghost that replays the player's pose + re-fires the primary.
var _echo_ghost: Node2D = null
var _echo_buf: Array = []            # ring buffer of {pos, fired} samples
var _echo_fired_this_frame: bool = false
const ECHO_BUF_MAX := 64             # ~1s of samples at 60fps (delay caps below this)
# Per-mode activation tell: a glow aura on the ship (tinted by mode) while active, plus a
# one-shot expanding pulse on activation. Phase/Hyper/Echo/Thief keep their signatures too.
var _mode_aura: CanvasItem = null
var _intangible: bool = false        # Phase: collision fully off (bullets pass through)
# Aura colours indexed by ShiftMode (KEEP IN SYNC): Focus Phase Hyper Rush Refire Echo Thief Reflect.
const _MODE_AURA_COLORS := [
	Color(0.4, 0.7, 1.0),   # FOCUS  cyan
	Color(0.2, 0.5, 1.0),   # PHASE  blue
	Color(1.0, 0.5, 0.0),   # HYPER  orange
	Color(0.4, 1.0, 0.6),   # RUSH   green
	Color(1.0, 0.45, 0.45), # REFIRE red
	Color(0.55, 0.85, 1.0), # ECHO   cyan
	Color(0.72, 0.32, 1.0), # THIEF  purple
	Color(0.95, 0.85, 0.35),# REFLECT gold
]

var can_shoot: bool = true
# Primary fire cadence: a carried-residual countdown that REPLACES the GunCooldown
# Timer as the firing gate. The Timer rounded every interval UP to the next whole
# frame and threw away the sub-frame remainder, so full-auto fire ran slow and the
# cadence slipped (firing intervals weren't aligned to the 60 Hz tick). _gun_cd_t
# counts down each frame and banks the (negative) overshoot into the next shot, so
# the average rate matches the configured `cooldown` exactly. Carry is capped at one
# frame (FIRE_CARRY) so a lag hitch can't bank a catch-up burst. GunCooldown stays
# in the scene only as the value mirror weapon_part writes + _cache_blaster_config
# reads — it is no longer started.
var _gun_cd_t: float = 0.0
const FIRE_CARRY: float = 1.0 / 60.0
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
const SHIELD_SHADER = preload("res://graphics/hex_shield.gdshader")  # committed (Roman 2026-06-11)
const ShieldRingFx = preload("res://scripts/effects/shield_ring_fx.gd")
var _shield_ring: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_fx = null   # ShieldRingFx: Sparse Plates base + fraction fill/flicker + hit-flash + collapse

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
var _mg_stop_pending: bool = false

# Rotary Laser audio — spin-up charge, then a rapid random "pew" per shot while
# firing (replaces the old sustained loop). The fire rate is ~20/s (base_cooldown
# 0.05), so the per-shot SFX is throttled to a sane cadence and the player node
# is polyphonic so the pews overlap cleanly.
const RL_CHARGE_DURATION: float = 0.4
const RL_SHOOT_SFX_MIN_MS: int = 80     # min gap between rotary shoot pews
const PULSE_SHOOT_SFX_MIN_MS: int = 80  # min gap between pulse shoot clips (~16/s fire)
var _rl_shoot_streams: Array = []
var _rl_shoot_last_ms: int = 0
var _pulse_shoot_last_ms: int = 0
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
		# Module bay: apply the equipped modules (the LIST, separate from the pegboard
		# above) — the unified "apply everything" loop. run_state seeds the default Shield Core.
		if "modules" in run and run.modules is Array:
			for m in run.modules:
				if m != null:
					m.apply(self)
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
	var ShadowFx = load("res://scripts/effects/shadow_fx.gd")
	ShadowFx.attach_shadow($Ship)
	# New ship layers (Roman 2026-06-09 player-art pass): GlowMask = engine glowmask (#00d3ff,
	# fades to half on move-back); Livery = shader-recolored decoration (random per-patrol tint);
	# EngineL/R = engine-trail markers (#00d3ff trails, above the sprites).
	_setup_ship_visuals()
	_install_damage_material()
	start()

const ENGINE_GLOW_COLOR := Color(0.0, 0.827, 1.0)   # #00d3ff (engine trails)
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")  # per-category HDR glow multipliers
const PLAYER_TRAIL_DRIFT := 160.0                    # px/s downward exhaust drift (hovering plume)

# Damage-overlay shader (Roman 2026-06-15): the player now gets the SAME health-driven damage
# overlay enemies use (enemy_base._install_damage_material) — the hull body darkens + frays as
# hull drops. Installed on the Ship body sprite; sensitivity ramps with missing hull.
const DamageOverlayShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoiseTex = preload("res://resources/noise_damage.tres")
const _DamageEdgeTex = preload("res://resources/edge_distance_flat.tres")
var _damage_material: ShaderMaterial = null


func _install_damage_material() -> void:
	if not has_node("Ship"):
		return
	var spr: Sprite2D = $Ship
	if spr.material != null:
		return   # don't stomp an existing material
	var mat := ShaderMaterial.new()
	mat.shader = DamageOverlayShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
	mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	spr.material = mat
	_damage_material = mat
	if not hull_changed.is_connected(_on_hull_changed_damage):
		hull_changed.connect(_on_hull_changed_damage)
	_update_damage_visual()


func _on_hull_changed_damage(_max_h, _h) -> void:
	_update_damage_visual()


# Ramp the overlay linearly in MISSING hull (0 at full, 0.6 at 1 hull) — mirrors the enemy formula.
func _update_damage_visual() -> void:
	if _damage_material == null or max_hull <= 0:
		return
	var denom: float = maxf(float(max_hull) - 1.0, 1.0)
	var lvl: float = clampf(0.6 * (float(max_hull) - float(hull)) / denom, 0.0, 0.6)
	_damage_material.set_shader_parameter("sensitivity", lvl)


# Wire up the new ship-art layers (Roman 2026-06-09): engine glowmask tint, the two #00d3ff
# engine trails, and the per-patrol livery recolor.
func _setup_ship_visuals() -> void:
	# Engine glowmask — HDR-bright by the tuned "engines" multiplier so the WorldEnvironment bloom
	# lights it (Roman 2026-06-22). modulate.a is eased in _process (half opacity while moving back),
	# so the engine dims on a move-back without losing the HDR rgb.
	if has_node("Ship") and $Ship.has_node("GlowMask"):
		var gm: Sprite2D = $Ship.get_node("GlowMask")
		gm.modulate = VfxGlow.prod_hdr("engines")
		gm.material = null
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


var _damage_fx_seq: int = 0

func _setup_smoke_trail() -> void:
	# Damage fire + smoke appear at a RANDOM point each run — sprite centre, an engine
	# marker, or a wing launch marker — and a SECOND point fades in as damage deepens
	# (Roman 2026-06-11). The fire shader no longer widens with damage (engine_torch).
	var pts := _damage_fx_points()
	if pts.is_empty():
		return
	# Damage tells START at 50% damage of the CURRENT max hull, regardless of hull
	# modifiers (Roman 2026-06-11). activate_below is a damage FRACTION (1 - hull/max),
	# so 0.5 = half the current max no matter how many pips that is — fixing the old
	# 0.01 ("first pip"), which on a bigger max hull triggered far sooner than half.
	_attach_damage_point(pts[0], 0.5)         # first point: shows at 50% hull lost
	if pts.size() > 1:
		_attach_damage_point(pts[1], 0.78)    # second point: deepens further toward death


# Candidate damage-tell anchors (player-local), shuffled: centre + REAL engine + wing
# markers. Fixed 2026-06-11: was `_muzzle_offset("Engine", ...)` (an exact-path lookup)
# which only matched ship A's single "Engine" marker — ships B/C use EngineL/EngineR
# and silently fell back to a generic offset, so the fire/smoke didn't sit on a real
# marker. Now finds every Engine* / LaunchWing* marker recursively, on any ship.
func _damage_fx_points() -> Array:
	var pts := [Vector2(0.0, 0.0)]   # sprite centre — always valid
	for m in find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			pts.append(to_local((m as Node2D).global_position))
	for wm in ["LaunchWingL", "LaunchWingR"]:
		var n := find_child(wm, true, false)
		if n is Node2D:
			pts.append(to_local((n as Node2D).global_position))
	pts.shuffle()
	return pts


# One fire (EngineTorch) + smoke (DamageSmokeTrail) pair at a local anchor, gated to
# appear below the given hull fraction.
func _attach_damage_point(local: Vector2, below: float) -> void:
	var TrailCls = preload("res://scripts/effects/damage_smoke_trail.gd")
	var trail = TrailCls.new()
	trail.name = "DamageSmokeTrail_%d" % _damage_fx_seq
	trail.activate_below = below
	trail.emit_local = local
	add_child(trail)
	trail.set_player(self)
	var EngineTorchCls = preload("res://scripts/effects/engine_torch.gd")
	var torch = EngineTorchCls.attach_to_player(self, local, below)
	if torch != null:
		torch.name = "EngineTorch_%d" % _damage_fx_seq
	# Fire-spark trail at the same marker (Roman 2026-06-11), gated on the same hull
	# threshold as the torch/smoke so all three damage tells appear together.
	var SparkTrailCls = preload("res://scripts/effects/spark_trail_fx.gd")
	var sparks = SparkTrailCls.attach_to_player(self, local, below)
	if sparks != null:
		sparks.name = "SparkTrail_%d" % _damage_fx_seq
	_damage_fx_seq += 1


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
	var loop_stream: AudioStream = load("res://assets/audio/weapons/player/Machinegun-Loop-LP.ogg")
	if loop_stream is AudioStreamOggVorbis:
		(loop_stream as AudioStreamOggVorbis).loop = true
	_mg_loop_player = AudioStreamPlayer2D.new()
	_mg_loop_player.name = "MgLoop"
	_mg_loop_player.stream = loop_stream
	_mg_loop_player.volume_db = -3.0
	_mg_loop_player.pitch_scale = 0.92
	_mg_loop_player.bus = "SFX"
	add_child(_mg_loop_player)

	var end_stream: AudioStream = load("res://assets/audio/weapons/player/Machinegun-End-LP.ogg")
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
		load("res://assets/audio/weapons/player/rotary_laser_shoot_1.ogg"),
		load("res://assets/audio/weapons/player/rotary_laser_shoot_2.ogg"),
		load("res://assets/audio/weapons/player/rotary_laser_shoot_3.ogg"),
		load("res://assets/audio/weapons/player/rotary_laser_shoot_4.ogg"),
		load("res://assets/audio/weapons/player/rotary_laser_shoot_5.ogg"),
		load("res://assets/audio/weapons/player/rotary_laser_shoot_6.ogg"),
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
	var start_stream: AudioStream = load("res://assets/audio/weapons/player/autocannon_start.ogg")
	_ac_start_player = AudioStreamPlayer2D.new()
	_ac_start_player.name = "AutocannonStart"
	_ac_start_player.stream = start_stream
	_ac_start_player.volume_db = -3.0
	_ac_start_player.bus = "SFX"
	add_child(_ac_start_player)

	var stop_stream: AudioStream = load("res://assets/audio/weapons/player/autocannon_stop.ogg")
	_ac_stop_player = AudioStreamPlayer2D.new()
	_ac_stop_player.name = "AutocannonStop"
	_ac_stop_player.stream = stop_stream
	_ac_stop_player.volume_db = -3.0
	_ac_stop_player.bus = "SFX"
	add_child(_ac_stop_player)


func _setup_mg_stop_audio() -> void:
	# Minigun stop sound (plays when firing ends, interruptible if firing resumes).
	var stop_stream: AudioStream = load("res://assets/audio/weapons/player/minigun_stop.ogg")
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

	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1) # shader drives final color
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_ring.size = Vector2(22, 22)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)

	# Shared shield driver (Sparse Plates base look + charge-fraction fill/flicker + hit-flash +
	# collapse). The ring starts invisible (alpha 0 / scale 0); start()'s initial sync raises it.
	_shield_fx = ShieldRingFx.new(_shield_mat, _shield_ring, ShieldRingFx.PLAYER_COLOR)

func start() -> void:
	show()
	is_alive = true
	position = Vector2(Playfield.CENTER.x, screensize.y - 30)
	# Run-level upgrades (outpost purchases) feed into max_hull, max_shield,
	# and speed_multiplier here so every combat scene picks up the latest state.
	apply_run_upgrades()
	shield = max_shield  # combat level starts fully-shielded
	# Module bay — per-level resets: Backup Shield Capacitor fires once per level; the
	# Reflective Shield counter starts fresh each combat.
	_backup_cap_used = false
	_reflect_hit_count = 0
	# Smart Mounts: cache the blaster turret config + force the primary active so the
	# pipeline drives it. Runs after apply_run_upgrades (module flags are set in _ready).
	_setup_smart_mounts()
	# Hull loaded from Run.current_hull via start() context (set in apply_run_upgrades).
	can_shoot = true
	_gun_cd_t = 0.0
	$GunCooldown.wait_time = cooldown  # value mirror only; not started (see _gun_cd_t)
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
	# Shift-mode charges: always full + inactive at combat start.
	mode_charges = mode_charges_max
	mode_active_t = 0.0
	_mode_regen_acc = 0.0
	mode_charges_changed.emit(mode_charges, mode_charges_max)
	mode_duration_changed.emit(mode_active_t, mode_duration)
	# Initial shield-ring visibility matches starting shield.
	_set_shield_ring_alpha(1.0 if shield > 0 else 0.0, 0.0)

func _process(delta: float) -> void:
	if not is_alive:
		return
	if _invuln_t > 0.0:
		_invuln_t = max(0.0, _invuln_t - delta)
	# Module bay — Repair Nanites: after MODULE_REPAIR_DELAY undamaged, regen +1 hull pip
	# every module_regen_interval s, gated to max_hull − 1 (can't fully self-heal). No-op
	# unless a Repair Nanites is equipped (interval 0).
	if module_regen_interval > 0.0:
		_repair_undamaged_t += delta
		if _repair_undamaged_t >= MODULE_REPAIR_DELAY and hull < max_hull - 1:
			_repair_tick_t += delta
			if _repair_tick_t >= module_regen_interval:
				_repair_tick_t = 0.0
				set_hull(mini(max_hull - 1, hull + 1))
	# Module bay — Overclock Core: the sustained-fire ramp decays to 0 after a no-fire gap.
	if module_overclock_max > 0.0:
		_overclock_idle_t += delta
		if _overclock_idle_t > OVERCLOCK_RESET_DELAY:
			_overclock_ramp = 0.0
	# Secondary cooldown ticks every frame regardless of input — so the
	# weapon recharges in the background and a tap fires immediately
	# whenever it's ready.
	# Cap one frame past ready so the sub-frame overshoot can bank into the next
	# shot (consumers subtract secondary_cooldown rather than zeroing) — same
	# tick-alignment fix as the primary; carry stays bounded to one frame.
	_secondary_t = min(_secondary_t + delta, _eff_secondary_cd() + FIRE_CARRY)
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
	# All Shift modes run through ONE unified runtime: press Shift to spend a charge and
	# activate for a duration; the per-mode effect is dispatched on active_mode. The only
	# movement-speed effect now is Rush's transient boost (Focus no longer slows — it's a
	# crit window; the old precision dot/hitbox is retired, see focus_mode.gd).
	_tick_shift_mode(delta)
	var speed_mode_mult: float = 1.0
	if _rush_on():
		speed_mode_mult = 1.0 + rush_speed_bonus   # Rush: minor speed surge while active
	# Thrusters / Armor Plating upgrades feed into speed_multiplier;
	# applied here so the runtime stat reflects the live upgrade state.
	# Movement is delta-scaled (framerate-independent). Clamp the step to a
	# 30fps-equivalent ceiling so a frame hitch / huge delta can't teleport the
	# ship across the playfield (matches enemy_core's delta cap). Roman 2026-06-01.
	# Clamp effective speed (engine/wing parts can stack past it) to the 8 px/f
	# readability ceiling so the ship stays controllable.
	var eff_speed: float = minf(speed * speed_multiplier * speed_mode_mult, ClarityRules.ABS_MAX_SPEED)
	_move_velocity = input * eff_speed
	position += _move_velocity * minf(delta, 1.0 / 30.0)
	position = Playfield.clamp_pos(position, 8.0)
	# Bleed off any residual tractor-beam momentum (Abductor grab) once it stops pulling this frame.
	_decay_pull_velocity(delta)
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
	# Hyper mode: hands-off full-auto — force the primary trigger on (the blaster fires
	# alongside it below, and the secondary is forced too). No ammo cost (gated elsewhere).
	if _hyper_on():
		fire_held = true
	# Phase mode: while phased out the player is intangible AND cannot hit bullets
	# or enemies — lock off primary offense (secondary is gated below).
	if _phase_on():
		fire_held = false
	# Passive Energy Routers — track trigger idleness for the shield-regen boost.
	# fire_held already folds in autofire + phase, so this reads true "shooting" state.
	if fire_held:
		_shot_recency = 0.0
	else:
		_shot_recency += delta
	# --- Smart Mounts: runtime toggle (S), manual-fire routing + auto-turrets ---
	# When ENABLED a mounted cannon auto-fires (the trigger drives the OTHER cannon; both
	# mounted = fully hands-off). When DISABLED the turret stands down and the weapon reverts
	# to a normal manual primary (trigger fires the active cannon, G-swap unlocked). The blaster
	# fires via direct-spawn, the primary via the real fire_primary() pipeline.
	if Input.is_action_just_pressed("smart_mount_toggle") and (module_blaster_mount or module_primary_mount):
		_mounts_enabled = not _mounts_enabled
		_show_mount_toast(_mounts_enabled)
		if _mounts_enabled:
			_setup_smart_mounts()                     # re-force the primary active + re-cache blaster
	# Primary cooldown recovery (carried-residual; see _gun_cd_t decl). Ticked here,
	# before any fire_primary() call this frame, so the gun is ready THIS frame when
	# the interval elapses — no parent-before-child one-frame Timer slip.
	if not can_shoot:
		_gun_cd_t -= delta
		if _gun_cd_t <= 0.0:
			can_shoot = true
			_gun_cd_t = maxf(_gun_cd_t, -FIRE_CARRY)
	_blaster_cd_t = maxf(_blaster_cd_t - delta, -FIRE_CARRY)
	var _manual_blaster: bool = false
	var _mounts_on: bool = _mounts_active()
	if _mounts_on:
		var _has_primary: bool = has_node("/root/Run") and get_node("/root/Run").cannon_pool.size() > 1
		if module_blaster_mount and module_primary_mount:
			fire_held = false                         # both auto
		elif module_primary_mount:
			_manual_blaster = fire_held               # primary auto; manual trigger = blaster
			fire_held = false
		elif module_blaster_mount and not _has_primary:
			fire_held = false                         # blaster auto, no primary to manual-fire
	if _mounts_on and is_alive and not _phase_on():
		if module_blaster_mount:
			_update_blaster_mount(delta)
		if module_primary_mount:
			_update_primary_mount(delta)
		if _manual_blaster and _blaster_cd_t <= 0.0:
			_fire_blaster_bolt(0.0)                    # manual blaster fires straight up
			_blaster_cd_t += _blaster_cooldown
	# Hyper: the blaster fires ALONGSIDE your active cannon (the all-weapons barrage), even
	# without a Smart Mount — drive the blaster direct-spawn on its own cadence.
	if _hyper_on() and is_alive and _blaster_cd_t <= 0.0:
		if _blaster_bullet_scene == null and has_node("/root/Run"):
			_cache_blaster_config(get_node("/root/Run"))
		_fire_blaster_bolt(0.0)
		_blaster_cd_t += _blaster_cooldown
	_update_mount_sight(_mounts_on)                   # aiming laser sight (hidden when off)
	# Pulse Laser dispersion: it ACCRUES while the trigger is HELD (in _fire_pulse_laser).
	# RELEASING the trigger recovers spread (PULSE_DISPERSION_DECAY °/s) + resets the
	# accuracy-window counter. Keyed on fire_held — NOT on whether a shot landed this
	# exact frame — so the sparse cadence (a shot every few frames) doesn't reset the
	# burst between shots (Roman 2026-06-11 fix: dispersion + colour weren't building).
	if not (fire_held and weapon_style == WS.WeaponStyle.PULSE_LASER):
		if _pulse_dispersion > 0.0:
			_pulse_dispersion = maxf(0.0, _pulse_dispersion - PULSE_DISPERSION_DECAY * delta)
		_pulse_shot_count = 0
	# Primary swap (Q): toggle which equipped cannon FIRES — the unlimited Blaster
	# (fallback) or the acquired Primary gun. Re-applies the new active cannon so
	# bullet_scene / cooldown / damage / SFX swap atomically. No-op if no primary.
	# Smart Mount: the swap (G) is locked only while a mount is ACTIVE (equipped + enabled) —
	# toggling the mount off (S) returns normal manual control + swap.
	if Input.is_action_just_pressed("primary_swap") and not _mounts_active():
		_swap_active_primary()
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
	# Hyper forces the secondary trigger too (held-type secondaries: bullet/beam/burst).
	var sec_held: bool = (Input.is_action_pressed("shoot2") or _hyper_on()) and not _phase_on()
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

# ---- Shift modes (the unified system) -----------------------------------
# One runtime (_tick_shift_mode) drives all three modes: press Shift → spend a charge →
# active for mode_duration → charges refill per the mode's rule. The per-mode EFFECT is
# dispatched on active_mode. Design: docs/shift_mode_system_2026-06-08.md.

# Screen post-FX aberration request, read each frame by CombatPostFx (renderer-polish
# D3, 2026-06-11): the aggressive Shift-modes split the screen channels slightly.
# Hyper overcharge holds a steady split; a phase dash punches a stronger one. 0 = none.
func postfx_aberration() -> float:
	var a: float = 0.0
	if _hyper_on():
		a = maxf(a, 0.0026)
	if _phase_on():
		a = maxf(a, 0.0045)
	return a


# Called by ModePart.apply/unapply when the equipped Shift mode changes. Pulls the part's
# unified params (duration / charges / regen) + Hyper's Mk effect tunables, resets state.
func _on_mode_changed() -> void:
	mode_active_t = 0.0
	_mode_regen_acc = 0.0
	_clear_hyper_outline()
	_set_phase_glow(false)
	_set_mode_field(false)
	_set_intangible(false)
	_set_mode_aura(false, Color.WHITE)
	_clear_echo_ghost()
	_echo_buf.clear()
	if mode_part != null:
		var mk: int = int(mode_part.mark) if "mark" in mode_part else 1
		if mode_part.has_method("mode_duration"):
			# Sector Conditions — Better Modes scale the cached duration; _tick_shift_mode
			# consumes it untouched. Null-safe: identity when no Condition set it.
			var _md: float = float(mode_part.mode_duration(mk))
			var _run_md = _run_ref()
			if _run_md != null:
				_md *= _run_md.cond_scalar("player.mode_duration_mult")
			mode_duration = maxf(0.1, _md)
		if mode_part.has_method("mode_charges"):
			mode_charges_max = maxi(1, int(mode_part.mode_charges(mk)))
		if mode_part.has_method("mode_regen_kind"):
			mode_regen_kind = int(mode_part.mode_regen_kind())
		if mode_part.has_method("mode_regen_secs"):
			mode_regen_secs = maxf(0.1, float(mode_part.mode_regen_secs()))
		if mode_part.has_method("mode_kills_per_charge"):
			mode_kills_per_charge = maxi(1, int(mode_part.mode_kills_per_charge()))
		# Per-mode effect tunables (Hyper's effect is autofire-all + free ammo — no
		# extra tunables; its Mk scales duration/charges via the getters above).
		if active_mode == ShiftMode.FOCUS:
			if mode_part.has_method("crit_chance_at_mark"):
				focus_crit_chance = float(mode_part.crit_chance_at_mark(mk))
		elif active_mode == ShiftMode.RUSH:
			if mode_part.has_method("speed_bonus_at_mark"):
				rush_speed_bonus = float(mode_part.speed_bonus_at_mark(mk))
			elif "speed_bonus" in mode_part:
				rush_speed_bonus = float(mode_part.speed_bonus)
		elif active_mode == ShiftMode.REFIRE:
			if mode_part.has_method("fire_bonus_at_mark"):
				refire_fire_bonus = float(mode_part.fire_bonus_at_mark(mk))
		elif active_mode == ShiftMode.REFLECT:
			if mode_part.has_method("reflect_chance_at_mark"):
				reflect_chance = float(mode_part.reflect_chance_at_mark(mk))
		elif active_mode == ShiftMode.THIEF:
			if "regen_per_hit" in mode_part:
				thief_regen_per_hit = maxi(1, int(mode_part.regen_per_hit))
			if "catch_radius" in mode_part:
				thief_catch_radius = maxf(8.0, float(mode_part.catch_radius))
		elif active_mode == ShiftMode.ECHO:
			if "delay" in mode_part:
				echo_delay = maxf(0.05, float(mode_part.delay))
	mode_charges = mode_charges_max  # start full
	# mode_changed first so the HUD rebuilds its pips/colour for the new mode, THEN the
	# charge + duration values populate the freshly-built meter.
	mode_changed.emit(active_mode)
	mode_charges_changed.emit(mode_charges, mode_charges_max)
	mode_duration_changed.emit(mode_active_t, mode_duration)


# Unified Shift-mode tick (called from _process). Activation → countdown → charge regen →
# per-mode effect dispatch. Focus's speed cut is read off _focus_on() back in _process.
func _tick_shift_mode(delta: float) -> void:
	# 1. Activate: tap Shift, hold a charge, not already running.
	if Input.is_action_just_pressed("focus") and mode_charges > 0 and not mode_is_active():
		mode_charges -= 1
		mode_active_t = mode_duration
		if active_mode == ShiftMode.PHASE:
			_phase_ai_acc = PHASE_AI_INTERVAL  # drop a ghost immediately on entry
		if active_mode >= 0 and active_mode < _MODE_AURA_COLORS.size():
			_mode_activation_pulse(_MODE_AURA_COLORS[active_mode])  # one-shot expanding flash
		mode_charges_changed.emit(mode_charges, mode_charges_max)
		mode_duration_changed.emit(mode_active_t, mode_duration)
	# 2. Countdown the active window.
	if mode_active_t > 0.0:
		mode_active_t = max(0.0, mode_active_t - delta)
		mode_duration_changed.emit(mode_active_t, mode_duration)
	# 3. Refill charges while idle (TIME modes here; KILLS handled in on_enemy_killed).
	if mode_charges < mode_charges_max and not mode_is_active() and mode_regen_kind == ModeRegen.TIME:
		_mode_regen_acc += delta
		if _mode_regen_acc >= mode_regen_secs:
			_mode_regen_acc -= mode_regen_secs
			mode_charges = mini(mode_charges_max, mode_charges + 1)
			mode_charges_changed.emit(mode_charges, mode_charges_max)
	# 4. Per-mode effect dispatch.
	# Generic tell: a glow aura tinted by the active mode (every mode lights up).
	if mode_is_active() and active_mode >= 0 and active_mode < _MODE_AURA_COLORS.size():
		_set_mode_aura(true, _MODE_AURA_COLORS[active_mode])
	else:
		_set_mode_aura(false, Color.WHITE)
	# Phase: TRUE intangibility — collision OFF so bullets pass clean through (no impact,
	# no hit sound), plus i-frames + after-image ghosts. Rush: i-frames only (impacts land
	# but deal no damage) + a speed-blur after-image; offense stays on.
	_set_intangible(_phase_on())
	if _phase_on() or _rush_on():
		_invuln_t = max(_invuln_t, mode_active_t)
		_phase_ai_acc += delta
		if _phase_ai_acc >= PHASE_AI_INTERVAL:
			_phase_ai_acc = 0.0
			_spawn_phase_afterimage()
	# Thief steals + Reflect bounces — both via the bullet-intercept field (Thief also
	# raises its purple sphere).
	_set_mode_field(_thief_on() or _reflect_on())
	# Echo: drive the delayed firing ghost while active.
	_tick_echo(delta)
	# Hyper: pulsing orange outline tell while active.
	if _hyper_on():
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
	# Pulse frequency rises from SLOW→FAST as the active window empties.
	var frac: float = 0.0
	if mode_duration > 0.0:
		frac = clampf(1.0 - mode_active_t / mode_duration, 0.0, 1.0)
	var hz: float = lerpf(HYPER_PULSE_HZ_SLOW, HYPER_PULSE_HZ_FAST, frac)
	_hyper_pulse_t += delta * hz
	_hyper_outline.modulate.a = 0.30 + 0.70 * (0.5 + 0.5 * sin(_hyper_pulse_t * TAU))


func _clear_hyper_outline() -> void:
	if _hyper_outline != null and is_instance_valid(_hyper_outline):
		_hyper_outline.queue_free()
	_hyper_outline = null


# Mode field: a bullet-intercept Area2D shared by Thief + Reflect. Same detection mask as
# the player's hurtbox, slightly larger so it catches bullets BEFORE the hurtbox (reliable).
# monitorable=false so bullets never try to damage the field itself. Thief steals bullets
# (→ shield) + shows a purple sphere; Reflect bounces a chance of them back at enemies.
func _set_mode_field(on: bool) -> void:
	if on:
		if _mode_field == null or not is_instance_valid(_mode_field):
			_mode_field = Area2D.new()
			_mode_field.name = "ModeField"
			_mode_field.collision_layer = 0
			_mode_field.collision_mask = collision_mask
			_mode_field.monitoring = true
			_mode_field.monitorable = false
			var cs := CollisionShape2D.new()
			var circ := CircleShape2D.new()
			circ.radius = thief_catch_radius if _thief_on() else REFLECT_FIELD_RADIUS
			cs.shape = circ
			_mode_field.add_child(cs)
			add_child(_mode_field)
			_mode_field.area_entered.connect(_on_mode_field_hit)
		if _thief_on():
			_spawn_thief_sphere()
		else:
			_clear_thief_sphere()
	else:
		if _mode_field != null and is_instance_valid(_mode_field):
			_mode_field.queue_free()
		_mode_field = null
		_clear_thief_sphere()


# A bullet entered the field. Thief steals it (delete + bank shield). Reflect bounces a
# chance of them back at enemies; a failed roll leaves the bullet to hit the player.
func _on_mode_field_hit(area: Area2D) -> void:
	if area == null or not is_instance_valid(area) or not area.is_in_group("bullets"):
		return
	if _thief_on():
		area.queue_free()
		if shield < max_shield:
			set_shield(mini(max_shield, shield + thief_regen_per_hit))
			_pulse_shield_ring()
	elif _reflect_on():
		if randf() < reflect_chance and area.has_method("reflect_to_enemies"):
			area.reflect_to_enemies()


func _clear_thief_sphere() -> void:
	if _thief_sphere != null and is_instance_valid(_thief_sphere):
		_thief_sphere.queue_free()
	_thief_sphere = null


# Phase: toggle the player's collision OFF so enemy fire passes clean through (no impact,
# no hit sound, no damage) — true intangibility. Restored on exit. set_deferred is
# physics-flush safe. NOTE: also makes the player pass through enemy ships (by design).
func _set_intangible(on: bool) -> void:
	if on == _intangible:
		return
	_intangible = on
	set_deferred("monitoring", not on)
	set_deferred("monitorable", not on)


# Generic per-mode tell: a soft glow aura on the ship, tinted to the active mode's colour,
# shown while active. Created once per activation (color baked at creation); cleared on exit.
func _set_mode_aura(on: bool, color: Color) -> void:
	if on:
		if (_mode_aura == null or not is_instance_valid(_mode_aura)) and has_node("Ship"):
			_mode_aura = GlowFx.attach_glow($Ship, color, 1.8, 0.6)
	else:
		if _mode_aura != null and is_instance_valid(_mode_aura):
			_mode_aura.queue_free()
		_mode_aura = null


# One-shot activation flash: an expanding, fading glow ring in the mode's colour.
func _mode_activation_pulse(color: Color) -> void:
	if not has_node("Ship"):
		return
	var g := GlowFx.attach_glow($Ship, color, 1.0, 0.95)
	if g == null or not is_instance_valid(g):
		return
	var base_scale: Vector2 = g.scale
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", base_scale * 3.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(g.queue_free)


# Purple recolor of the hex-shield dome, scaled to the catch radius (visual only).
func _spawn_thief_sphere() -> void:
	if _thief_sphere != null and is_instance_valid(_thief_sphere):
		return
	_thief_mat = ShaderMaterial.new()
	_thief_mat.shader = SHIELD_SHADER
	_thief_mat.set_shader_parameter("alpha", 0.55)
	_thief_mat.set_shader_parameter("hit_strength", 0.0)
	_thief_mat.set_shader_parameter("shield_color", THIEF_SPHERE_COLOR)
	_thief_mat.set_shader_parameter("cells", 5.0)
	_thief_mat.set_shader_parameter("scroll", Vector2(0.0, 0.05))
	_thief_mat.set_shader_parameter("line_width", 0.2)
	_thief_mat.set_shader_parameter("rim_power", 3.0)
	_thief_mat.set_shader_parameter("fill_alpha", 0.12)
	_thief_mat.set_shader_parameter("flicker", 1.0)
	_thief_mat.set_shader_parameter("dome", 0.45)
	_thief_sphere = ColorRect.new()
	_thief_sphere.name = "ThiefSphere"
	_thief_sphere.color = Color(1, 1, 1, 1)   # shader drives final colour
	_thief_sphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = thief_catch_radius * 2.0
	_thief_sphere.size = Vector2(d, d)
	_thief_sphere.position = -_thief_sphere.size * 0.5
	_thief_sphere.material = _thief_mat
	_thief_sphere.z_index = 1
	add_child(_thief_sphere)


# Echo: each frame while active, record the player's pose + whether they fired, drive a
# translucent ghost to replay that pose `echo_delay` seconds late, and re-fire the primary
# from the ghost when the recorded frame fired. v1 mirrors PRIMARY fire only.
func _tick_echo(delta: float) -> void:
	if not _echo_on():
		if _echo_ghost != null:
			_clear_echo_ghost()   # fades out when the window ends
		_echo_buf.clear()
		return
	# Record this frame (the fired flag carries last frame's fire_primary — a 1-frame lag
	# that's invisible against the ~0.35s delay).
	_echo_buf.append({"pos": global_position, "fired": _echo_fired_this_frame})
	_echo_fired_this_frame = false
	if _echo_buf.size() > ECHO_BUF_MAX:
		_echo_buf.pop_front()
	if _echo_ghost == null or not is_instance_valid(_echo_ghost):
		_spawn_echo_ghost()
	if _echo_ghost == null or not is_instance_valid(_echo_ghost):
		return
	# Read the sample from echo_delay seconds ago (≈ delay/delta frames back).
	var frames_back: int = int(round(echo_delay / maxf(0.001, delta)))
	var raw_idx: int = _echo_buf.size() - 1 - frames_back
	var idx: int = maxi(0, raw_idx)
	var sample: Dictionary = _echo_buf[idx]
	_echo_ghost.global_position = sample.get("pos", global_position)
	# ONLY fire once genuine delayed history exists (raw_idx >= 0). Until then the buffer's
	# oldest sample is clamped at idx 0, and replaying its fired flag every frame would dump
	# a burst at activation — the bug Roman hit.
	if raw_idx >= 0 and bool(sample.get("fired", false)):
		_echo_fire_ghost_bolt()


func _spawn_echo_ghost() -> void:
	if not has_node("Ship"):
		return
	var ship := $Ship as Sprite2D
	if ship == null or ship.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = ship.texture
	g.hframes = ship.hframes
	g.vframes = ship.vframes
	g.frame = ship.frame
	g.flip_h = ship.flip_h
	g.flip_v = ship.flip_v
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	g.global_position = global_position
	g.z_index = -1
	g.modulate = Color(0.6, 0.85, 1.0, 0.6)   # translucent cyan echo
	if _ghost_add_mat == null:
		_ghost_add_mat = CanvasItemMaterial.new()
		_ghost_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = _ghost_add_mat
	var host: Node = get_parent() if get_parent() != null else get_tree().root
	host.add_child(g)
	_echo_ghost = g


# Fire one primary bolt straight up from the ghost (player's bullet + damage; no crit/mods).
func _echo_fire_ghost_bolt() -> void:
	if bullet_scene == null or _echo_ghost == null or not is_instance_valid(_echo_ghost):
		return
	var b: Node = bullet_scene.instantiate()
	_bullet_parent().add_child(b)
	if b is Node2D:
		(b as Node2D).z_index = -1
	if "damage" in b:
		b.damage = _wpn_dmg(bullet_damage)
	if b.has_method("start"):
		b.start(_echo_ghost.global_position + Vector2(0, -10), Vector2(0, -1))


# Detach + fade the ghost so it lingers a moment after Echo ends (it's parented to the world,
# so it survives the player). Idempotent.
func _clear_echo_ghost() -> void:
	var g := _echo_ghost
	_echo_ghost = null
	if g == null or not is_instance_valid(g):
		return
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.3)
	tw.tween_callback(g.queue_free)


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
			_phase_glow = GlowFx.attach_glow($Ship, PHASE_GLOW_COLOR, 1.6, 0.7)
	else:
		if _phase_glow != null and is_instance_valid(_phase_glow):
			_phase_glow.queue_free()
		_phase_glow = null


# KILLS-regen Shift modes (Phase) refill a charge per N kills. Wired from
# main._on_enemy_died (the bounty-award hook) so only player-caused kills count —
# off-screen departs don't.
func on_enemy_killed() -> void:
	# Module bay — Siphon Core: every Nth kill restores one shield charge (no-op unless
	# a Siphon Core is equipped). Runs regardless of shift mode, so it sits before the
	# mode-regen early-return below.
	if module_siphon_kills_per_charge > 0:
		_siphon_kill_count += 1
		if _siphon_kill_count >= module_siphon_kills_per_charge:
			_siphon_kill_count = 0
			if shield < max_shield:
				# Through set_shield so the HUD gets its (max, val) args and the
				# shield-ring fill updates (a bare emit() errored both handlers).
				set_shield(mini(max_shield, shield + 1))
	# Unified Shift-mode KILLS regen — only for modes that refill on kills (Phase).
	if mode_regen_kind != ModeRegen.KILLS or mode_charges >= mode_charges_max:
		return
	_mode_regen_acc += 1.0
	if _mode_regen_acc >= float(mode_kills_per_charge):
		_mode_regen_acc -= float(mode_kills_per_charge)
		mode_charges = mini(mode_charges_max, mode_charges + 1)
		mode_charges_changed.emit(mode_charges, mode_charges_max)


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
	# FLAT DAMAGE (Roman 2026-07-04): every hit costs the player exactly ONE — one shield HP,
	# or one hull pip — regardless of the source's own damage stat. Enemy bullets, missiles,
	# rockets, ship contact, mines, beams and bosses all normalize to 1 here. Difficulty scales
	# through VOLUME (more enemies / more bullets), not per-hit magnitude. This is also the single
	# choke point that makes the two-sided collision detection (projectile-side take_damage(damage)
	# vs the player-side _on_area_entered) deterministic — whichever wins the same-frame race now
	# applies the same 1. Placed BEFORE the "dangerous" block so that parked modifier, if ever
	# re-enabled, still doubles the flat base (1 → 2) as designed.
	amount = 1
	# Phase mode takes NO damage at all — handled by the full-duration i-frame the runtime
	# sets (_invuln_t = mode_active_t in _tick_shift_mode), caught at the i-frame check below.
	# (Bullet-absorb → +shield is now Thief mode's job, via its catch bubble.)
	# Sector Condition "Heavy Ordnance" (§4b): all incoming damage counts double. This is the ONE
	# Condition Roman sanctioned to BREAK the flat-damage rule ([[flat-player-damage]]) — the mult
	# lands AFTER the flat clamp above and BEFORE the i-frame check, so it burns 2 shield charges / 2
	# hull pips per hit. Read via the generic aggregator; empty active_conditions → scalar 1.0 → no-op.
	# (The old per-sector damage ramp `× (1 + 0.05 × sectors_cleared)` was dropped 2026-06-23 with the
	# single-sector switch — sectors_cleared stays 0 now.)
	var _run = get_node_or_null("/root/Run")
	if _run != null:
		amount = maxi(1, roundi(float(amount) * _run.cond_scalar("player.damage_taken_mult")))
	# I-frame window after a shield or hull hit.
	if _invuln_t > 0.0:
		return
	# (Reflect mode reverses incoming bullets at the mode field BEFORE they reach here, so
	# there's no reflect roll in the damage path — a bullet that gets here simply landed.)
	# Module bay — Repair Nanites: any landed hit resets the regen-delay timer.
	_repair_undamaged_t = 0.0
	_repair_tick_t = 0.0
	var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
	if shield > 0:
		# Shield absorbs full hit — no overflow to hull. Short i-frame only,
		# so a sustained bullet stream keeps draining the HP pool per hit.
		set_shield(max(0, shield - amount))
		# Module bay — Backup Shield Capacitor: the FIRST shield drop in a level dumps in
		# a % of max shield (once per level). Capped at max_shield.
		if module_backup_shield_pct > 0.0 and not _backup_cap_used:
			_backup_cap_used = true
			var back: int = maxi(1, int(round(float(max_shield) * module_backup_shield_pct)))
			set_shield(mini(max_shield, shield + back))
		# Module bay — Reflective Shield Tuning: every Nth absorbed bullet is bounced back
		# into the playfield at the nearest enemy.
		if module_reflect_n > 0:
			_reflect_hit_count += 1
			if _reflect_hit_count >= module_reflect_n:
				_reflect_hit_count = 0
				_reflect_bullet()
		_invuln_t = SHIELD_HIT_INVULN_SECONDS
		damaged.emit(0)
		_flash_shield_ring()
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
	# Sector Condition "Glass Patrol" (§4b): any hull damage is instant death — skip pips, shrug,
	# ablative and damage tells. The shield branch above already returned, so shields still absorb
	# normally; this fires only once the shield pool is empty and a hull hit lands. Every hull hit
	# is LETHAL under Glass Patrol, so the Touhou death-bomb save applies exactly as in the
	# hull-empty branch above (Roman 2026-07-09: the save is respected as normal) — a charged super
	# fires and the guaranteed i-frame saves you; otherwise the hit ends the run.
	# Empty active_conditions → flag false → no-op.
	if _run != null and _run.cond_flag("player.glass_hull"):
		if super_charges > 0 and super_part != null:
			fire_super()
			_invuln_t = maxf(_invuln_t, SHIELD_INVULN_SECONDS)
			if _invuln_t > 0.0:
				return
		die()
		return
	# Shrug: milestone perk — chance to absorb the hit with no pip loss.
	if hull_shrug_chance > 0.0 and randf() < hull_shrug_chance:
		return
	# Module bay — Ablative Plating: deterministically absorb every Nth hull hit (no pip loss).
	if module_ablative_n > 0:
		_ablative_hit_count += 1
		if _ablative_hit_count >= module_ablative_n:
			_ablative_hit_count = 0
			if has_node("Ship"):
				var _af = load("res://scripts/effects/hit_flash_fx.gd")
				_af.flash($Ship, _af.FLASH_SHIELD)
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
	# Shield-ring look tracks the charge fraction (fill_alpha up / flicker down as it fills).
	_apply_shield_state()
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
			$ShieldRegenTimer.wait_time = _effective_regen_delay()  # Capacitor + Energy Routers lower this
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
	_set_mode_field(false)  # and the Thief/Reflect field
	_set_intangible(false)  # restore collision
	_set_mode_aura(false, Color.WHITE)  # and the activation glow
	_clear_echo_ghost()       # and the Echo ghost
	mode_active_t = 0.0     # end any active Shift mode
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


# Pulse Laser shot: a 1px hitscan beam from the nose at an angle randomized within the
# current dispersion cone. Damages the nearest enemy along the beam, draws the glowing
# beam, and accrues dispersion past the accuracy window. (Roman 2026-06-11.)
func _fire_pulse_laser() -> void:
	var origin: Vector2 = global_position + _muzzle_offset("Ship/Muzzle", Vector2(0, -8))
	# Straight up ± a random angle inside the dispersion cone (full width = dispersion).
	var half: float = deg_to_rad(_pulse_dispersion) * 0.5
	var ang: float = randf_range(-half, half)
	var dir := Vector2(sin(ang), -cos(ang))
	var dmg: int = _wpn_dmg(bullet_damage)
	var hit := _pulse_hitscan(origin, dir, PULSE_RANGE)
	var enemy = hit["enemy"]
	if enemy != null and is_instance_valid(enemy):
		if enemy.has_method("take_hit"):
			enemy.take_hit(dmg)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
	_spawn_pulse_beam(origin, hit["point"])
	# Energy muzzle flash at the nose (Roman 2026-06-11: "muzzleflashes missing from
	# most weapons" — Pulse Laser was the last fire path with none). The rotary-laser
	# flash is the cyan-blue energy variant with a ~0.04s fade, matching the beam's
	# energy look and the weapon's rapid cadence.
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	if MuzzleFx:
		MuzzleFx.play_rotary_laser(origin, self)
	# Pulse fire SFX (Roman 2026-06-11): this fire path returns before the shared
	# per-shot SFX block, so play the pulse_laser_shoot_* pool here directly. Throttled
	# like the rotary laser — at ~16/s a voice-per-shot would machine-gun the clips.
	var pulse_now: int = Time.get_ticks_msec()
	if pulse_now - _pulse_shoot_last_ms >= PULSE_SHOOT_SFX_MIN_MS:
		_pulse_shoot_last_ms = pulse_now
		var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
		if WeaponSfx:
			WeaponSfx.play(get_tree().root, global_position, "pulse")
	# Accuracy: pinpoint for the first `pulse_accuracy_window` shots of a burst, then
	# +1° dispersion per shot up to the cap.
	_pulse_shot_count += 1
	if _pulse_shot_count > pulse_accuracy_window:
		_pulse_dispersion = minf(PULSE_MAX_DISPERSION, _pulse_dispersion + 1.0)


# Nearest enemy whose hitbox lies within PULSE_HIT_TOLERANCE px of the beam ray (and
# ahead of the muzzle). Returns {enemy, point} — point is the hit, or the beam's end.
func _pulse_hitscan(origin: Vector2, dir: Vector2, max_dist: float) -> Dictionary:
	var best_enemy = null
	var best_t: float = max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var to_e: Vector2 = (e as Node2D).global_position - origin
		var t: float = to_e.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		if (to_e - dir * t).length() <= PULSE_HIT_TOLERANCE:
			best_t = t
			best_enemy = e
	return {"enemy": best_enemy, "point": origin + dir * best_t}


# Module bay — Reflective Shield Tuning. Bounces an absorbed bullet back into the
# playfield as a player bolt aimed at the nearest enemy (straight up if the field is
# clear). Reuses the equipped primary's bullet scene + damage, so the reflect scales
# with the build. No-op without a primary cannon (nothing to reflect with).
func _reflect_bullet() -> void:
	if bullet_scene == null:
		return
	var target: Node2D = _nearest_enemy()
	var dir := Vector2(0, -1)
	if target != null:
		dir = (target.global_position - global_position).normalized()
	var b: Node = bullet_scene.instantiate()
	_bullet_parent().add_child(b)
	if b is Node2D:
		(b as Node2D).z_index = -1
	if "damage" in b:
		b.damage = _wpn_dmg(bullet_damage)
	if b.has_method("start"):
		b.start(global_position, dir)


# Nearest live enemy Node2D (squared-distance), or null if the field is clear.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var d: float = global_position.distance_squared_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


# ===== Smart Mounts (modules) =====

# Per-combat setup: reset turret state, cache the blaster's fire config, and force the
# primary active so fire_primary() drives it. Called from start() after apply_run_upgrades.
func _setup_smart_mounts() -> void:
	_blaster_aim = 0.0
	_primary_aim = 0.0
	_blaster_cd_t = 0.0
	_primary_mount_ready = true
	if not (module_blaster_mount or module_primary_mount):
		return
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	_cache_blaster_config(run)
	# Force the primary (cannon_pool[1]) active so the pipeline fires it; Q is locked.
	if run.cannon_pool.size() > 1 and run.active_cannon_idx != 1:
		run.active_cannon_idx = 1
		_reapply_active_cannon()


# Cache the blaster bolt scene / damage / cooldown from cannon_pool[0] so the direct-spawn
# turret can fire it even when the primary is the active (loaded) cannon.
func _cache_blaster_config(run) -> void:
	_blaster_bullet_scene = bullet_scene                 # fallback: whatever's loaded now
	_blaster_damage = maxi(1, bullet_damage)
	_blaster_cooldown = maxf(0.05, $GunCooldown.wait_time)
	_blaster_sfx_kind = WS.FireSfxKind.BLASTER_SMALL
	if run.cannon_pool.size() > 0:
		var bl = run.cannon_pool[0]
		if bl != null:
			if "bullet_scene" in bl and bl.bullet_scene != null:
				_blaster_bullet_scene = bl.bullet_scene
			if bl.has_method("_effective_damage_at_mark"):
				_blaster_damage = maxi(1, bl._effective_damage_at_mark(int(bl.mark)))
			if "base_cooldown" in bl:
				_blaster_cooldown = maxf(0.05, float(bl.base_cooldown))
			# Cache the blaster's OWN fire sound — fire_sfx_kind on the ship reflects the
			# forced-active PRIMARY while a Smart Mount is on, so the direct-spawn bolt would
			# otherwise be silent (regression: Primary Smart Mount muted the blaster).
			if bl.has_method("_fire_sfx_kind"):
				_blaster_sfx_kind = int(bl._fire_sfx_kind())
	if _blaster_bullet_scene == null:
		_blaster_bullet_scene = load("res://scenes/projectiles/bullet_blaster.tscn")
	# Sector Conditions — Faster Weapons shortens the direct-spawn blaster cadence at this
	# single computation point; the three _blaster_cd_t consumers all read this var.
	if _cond_fire_rate_mult != 1.0:
		_blaster_cooldown = maxf(0.05, _blaster_cooldown / _cond_fire_rate_mult)


# Nearest enemy inside the 120° front arc (±mount_arc of up) within mount_range, or null.
func _mount_target():
	var best = null
	var best_d: float = mount_range * mount_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var to_e: Vector2 = (e as Node2D).global_position - global_position
		# Bearing from the up axis: atan2(x, -y). 0 = straight up, ± toward the sides.
		if absf(atan2(to_e.x, -to_e.y)) > mount_arc:
			continue
		var d: float = to_e.length_squared()
		if d < best_d:
			best_d = d
			best = e
	return best


# Slew `cur` toward `target` by `rate` rad/s (clamped), returning the new aim.
func _slew_aim(cur: float, target: float, rate: float, delta: float) -> float:
	var step: float = maxf(rate, 0.5) * delta
	var diff: float = target - cur
	if absf(diff) <= step:
		return target
	return cur + signf(diff) * step


# Random dispersion in [-disp, disp] rad (0 when disp <= 0).
func _mount_dispersion(disp: float) -> float:
	if disp <= 0.0:
		return 0.0
	return randf_range(-disp, disp)


# Blaster turret: aim toward the nearest in-arc enemy, fire a direct-spawn bolt when lined up.
func _update_blaster_mount(delta: float) -> void:
	var tgt = _mount_target()
	var desired: float = 0.0
	if tgt != null:
		var to_e: Vector2 = tgt.global_position - global_position
		desired = clampf(atan2(to_e.x, -to_e.y), -mount_arc, mount_arc)
	_blaster_aim = _slew_aim(_blaster_aim, desired, module_blaster_traverse, delta)
	if tgt != null and _blaster_cd_t <= 0.0 and absf(_blaster_aim - desired) <= mount_fire_tolerance:
		_fire_blaster_bolt(_blaster_aim + _mount_dispersion(module_blaster_dispersion))
		_blaster_cd_t += _blaster_cooldown


# Primary turret: aim toward the nearest in-arc enemy, then auto-trigger fire_primary(aim).
# Regen lasers wait for a FULL recharge between magazines (spec).
func _update_primary_mount(delta: float) -> void:
	if not (has_node("/root/Run") and get_node("/root/Run").cannon_pool.size() > 1):
		return  # no equipped primary to drive
	var tgt = _mount_target()
	var desired: float = 0.0
	if tgt != null:
		var to_e: Vector2 = tgt.global_position - global_position
		desired = clampf(atan2(to_e.x, -to_e.y), -mount_arc, mount_arc)
	_primary_aim = _slew_aim(_primary_aim, desired, module_primary_traverse, delta)
	if tgt == null or absf(_primary_aim - desired) > mount_fire_tolerance:
		return
	# Regen-laser latch: dump the full magazine, then hold until it has recharged all the
	# way back ("wait for the ammo to fully regenerate before firing again").
	if ammo_recharge_rate > 0.0 and ammo_max > 0:
		if ammo >= ammo_max:
			_primary_mount_ready = true
		elif ammo <= 0:
			_primary_mount_ready = false
		if not _primary_mount_ready:
			return
	# Non-regen metered primary run dry: stand down and wait for ammo (an outpost refill) —
	# the mount does NOT fall back to the blaster (Roman 2026-06-14).
	if ammo_recharge_rate <= 0.0 and ammo_max > 0 and ammo <= 0:
		return
	fire_primary(_primary_aim + _mount_dispersion(module_primary_dispersion))


# Direct-spawn one blaster bolt in `aim` direction (rad, 0 = up). Mirrors the module
# damage scalars the manual blaster gets (Overcharge / De-Limiter) for parity.
# Sub-frame spawn correction (the spatial twin of the _gun_cd_t / _blaster_cd_t carry).
# A shot fired `late` seconds after its ideal moment is advanced along its travel
# vector by the distance it should already have covered, so an off-grid fire rate
# lays down an evenly-spaced stream instead of a one-frame 4/5 "beat". `late` is
# bounded by FIRE_CARRY (≤ one frame), so the forward nudge is ≤ ~8 px — invisible
# as a pop, but it removes the stream waviness. No-op when the bullet has no speed.
func _subframe_advance(b: Node, dir: Vector2, late: float) -> Vector2:
	if late <= 0.0 or not ("speed" in b):
		return Vector2.ZERO
	return dir * float(b.speed) * late


func _fire_blaster_bolt(aim: float) -> void:
	if _blaster_bullet_scene == null:
		return
	var b: Node = _blaster_bullet_scene.instantiate()
	_bullet_parent().add_child(b)
	if b is Node2D:
		(b as Node2D).z_index = -1
	if "damage" in b:
		var dmg: int = _blaster_damage
		if module_damage_mult != 1.0:
			dmg = int(round(float(dmg) * module_damage_mult))
		var _delim: float = _delimiter_bonus()
		if _delim > 0.0:
			dmg = int(round(float(dmg) * (1.0 + _delim)))
		# Sector Conditions weapon-damage choke — scale the NET (post module/delimiter).
		b.damage = _wpn_dmg(dmg)
	var dir := Vector2(sin(aim), -cos(aim))
	# Muzzle (bullet spawn + flash) rotates with the turret aim so the bolt leaves the
	# aimed barrel; aim 0 (manual / mount off) = the normal nose.
	var muzzle: Vector2 = global_position + _muzzle_offset("Ship/Muzzle", Vector2(0, -8)).rotated(aim)
	# Sub-frame spawn (see _subframe_advance): _blaster_cd_t still holds this shot's
	# negative residual here — the carry's += runs at the call site after this returns.
	muzzle += _subframe_advance(b, dir, clampf(-_blaster_cd_t, 0.0, FIRE_CARRY))
	if b.has_method("start"):
		b.start(muzzle, dir)
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	if MuzzleFx:
		MuzzleFx.play_energy(muzzle, self, aim)
	# Per-shot blaster SFX — mirrors fire_primary's cannon sound so the direct-spawn
	# blaster (Smart Mount auto-turret + manual-fire-under-primary-mount + Hyper barrage)
	# isn't silent. Uses the blaster's cached kind, NOT the ship's fire_sfx_kind (that
	# holds the forced-active primary's sound while a mount is on).
	if _blaster_sfx_kind != WS.FireSfxKind.NONE:
		var WeaponSfx = load("res://scripts/effects/weapon_sfx.gd")
		if WeaponSfx:
			WeaponSfx.play(get_tree().root, global_position, WS.sfx_kind_string(_blaster_sfx_kind))


# A mount is ACTIVE when equipped AND the runtime toggle (S) is on.
func _mounts_active() -> bool:
	return (module_blaster_mount or module_primary_mount) and _mounts_enabled


# Aiming sight line — a teal-green 1px Line2D from the ship center, sorted UNDER the hull,
# fading to transparent with distance. Follows the active turret's aim (primary-priority)
# and ends at the locked target, so the player sees where the gun is pointing. Hidden when
# mounts are off or there's no target in the arc.
func _update_mount_sight(active: bool) -> void:
	var aim: float = 0.0
	var has_aim: bool = false
	if active and module_primary_mount and has_node("/root/Run") and get_node("/root/Run").cannon_pool.size() > 1:
		aim = _primary_aim
		has_aim = true
	elif active and module_blaster_mount:
		aim = _blaster_aim
		has_aim = true
	var tgt = _mount_target() if has_aim else null
	if not has_aim or tgt == null:
		if _mount_sight != null:
			_mount_sight.visible = false
		return
	if _mount_sight == null:
		_build_mount_sight()
	_mount_sight.visible = true
	var dist: float = minf(mount_range, global_position.distance_to((tgt as Node2D).global_position))
	var dir := Vector2(sin(aim), -cos(aim))
	_mount_sight.points = PackedVector2Array([Vector2.ZERO, dir * dist])


func _build_mount_sight() -> void:
	_mount_sight = Line2D.new()
	_mount_sight.width = 1.0
	_mount_sight.z_index = -2          # under the ship sprite + bullets ("sorted under")
	_mount_sight.begin_cap_mode = Line2D.LINE_CAP_NONE
	_mount_sight.end_cap_mode = Line2D.LINE_CAP_NONE
	_mount_sight.antialiased = false
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([MOUNT_SIGHT_COLOR, Color(MOUNT_SIGHT_COLOR.r, MOUNT_SIGHT_COLOR.g, MOUNT_SIGHT_COLOR.b, 0.0)])
	_mount_sight.gradient = grad
	add_child(_mount_sight)


# A 1px additive glowing beam from origin→end, tinted white→#000fd8 by dispersion,
# that flashes briefly and frees. Parents to the player's world (combat scene), NOT
# the player — beams are world-space and must survive in the right viewport.
func _spawn_pulse_beam(origin: Vector2, end_pt: Vector2) -> void:
	var host: Node = get_parent()
	if host == null:
		host = self
	# Outer glow — a wider additive line UNDER the core beam (Roman 2026-06-11). HDR-bright by the
	# tuned "lasers" multiplier so the WorldEnvironment blooms it (Roman 2026-06-22). The 1px core
	# below keeps its white→blue dispersion tell.
	var glow := Line2D.new()
	glow.width = 3.0
	glow.default_color = Color(0.0, 0.07, 1.0, 0.55)   # #0012ff base; HDR comes from modulate
	glow.modulate = VfxGlow.prod_hdr("lasers")
	glow.add_point(origin)
	glow.add_point(end_pt)
	glow.z_index = 0
	glow.z_as_relative = false
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	host.add_child(glow)
	var gtw := glow.create_tween()
	gtw.tween_property(glow, "modulate:a", 0.0, 0.06)
	gtw.tween_callback(glow.queue_free)
	# Core beam — 1px, white -> #000fd8 by dispersion (the inner progression stays).
	var line := Line2D.new()
	line.width = 1.0
	var ratio: float = clampf(_pulse_dispersion / PULSE_MAX_DISPERSION, 0.0, 1.0)
	line.default_color = Color(1.0, 1.0, 1.0).lerp(PULSE_INACCURATE_COLOR, ratio)
	line.modulate = VfxGlow.prod_hdr("lasers")
	line.add_point(origin)
	line.add_point(end_pt)
	line.z_index = 1
	line.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # glows (HDR-bright white blooms)
	line.material = mat
	host.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.06)
	tw.tween_callback(line.queue_free)


# Passive Module bay contributions — default-safe (all no-op until a module applies).
# Set by equipped modules' apply()/unapply(); read in apply_run_upgrades + the fire path.
# See docs/passive_module_bay_2026-06-13.md.
var module_shield_bonus: int = 0             # Shield Core: +1 max shield charge per Mk
var module_damage_mult: float = 1.0          # Overcharge Core: primary-damage multiplier
var module_shield_charge_penalty: int = 0    # Overcharge Core: −1 max shield charge
var module_siphon_kills_per_charge: int = 0  # Siphon Core: 0 = off, else kills per +1 charge
var _siphon_kill_count: int = 0
var module_regen_interval: float = 0.0       # Repair Nanites: sec per +1 hull pip (0 = off)
var module_ablative_n: int = 0               # Ablative Plating: absorb every Nth hull hit (0 = off)
const MODULE_REPAIR_DELAY := 5.0             # seconds undamaged before nanite regen kicks in
var _repair_undamaged_t: float = 0.0
var _repair_tick_t: float = 0.0
var _ablative_hit_count: int = 0
var module_crit_chance: float = 0.0          # Targeting Computer: primary crit chance (×2 dmg, purple bolt)
var module_overclock_max: float = 0.0        # Overclock Core: max sustained-fire rate bonus (0 = off)
var module_delimiter_max: float = 0.0        # Critical System De-Limiter: max fire+dmg bonus at 1 hull (0 = off)
const OVERCLOCK_RAMP_PER_SHOT := 0.05        # ramp gained per shot held (≈20 shots to full; balance 2026-06-25)
const OVERCLOCK_RESET_DELAY := 0.35          # no-fire gap that resets the ramp
const MODULE_CRIT_COLOR := Color(0.85, 0.45, 1.35)  # purple HDR bolt tint on a crit shot
var _overclock_ramp: float = 0.0
var _overclock_idle_t: float = 0.0
# Converted-from-upgrade modules (Reinforced Hull / Thrusters / Shield Capacitor) — the
# former hull_mk / thrusters_mk / shield_cap_mk are now bay modules. Default-safe (no
# module = baseline). shield_regen_* default to the old hardcoded 5.0s delay / 1.0s ticks.
var module_hull_bonus: int = 0               # Reinforced Hull: +max_hull pips
var module_speed_pct: float = 0.0            # Thrusters: +speed fraction
var shield_regen_delay: float = 5.0          # Shield Capacitor lowers it (sec before regen begins)
var shield_regen_interval: float = 1.0       # Shield Capacitor lowers it (sec per +1 charge)
var module_backup_shield_pct: float = 0.0    # Backup Shield Capacitor: % of max shield restored on first drop
var _backup_cap_used: bool = false           # once per level — reset in start()
var module_reflect_n: int = 0                # Reflective Shield Tuning: reflect every Nth absorbed bullet (0 = off)
var _reflect_hit_count: int = 0
var module_ammo_restore_pct: float = 0.0     # Internal Micro Fabricator: % max ammo restocked on level clear
var module_energy_router_pct: float = 0.0    # Passive Energy Routers: regen delay/interval cut while not firing
var _shot_recency: float = 999.0             # sec since the primary trigger was last held (starts idle)
const ROUTER_IDLE_GRACE := 0.5               # trigger-idle grace before the Energy Routers boost engages

# Smart Mounts (modules) — auto-aiming turrets. A mounted cannon fires automatically at
# the nearest enemy inside a 120° front arc; the unmounted cannon stays manual; both
# mounted = fully hands-off. Blaster auto-fires via a light direct-spawn path; the primary
# rides the real fire_primary() pipeline (all weapon styles). Q-swap is locked while any
# mount is active and the primary is forced active so the pipeline drives it.
var module_blaster_mount: bool = false
var module_blaster_traverse: float = 0.0     # rad/s aim slew rate (Mk-scaled)
var module_blaster_dispersion: float = 0.0   # rad half-spread of shot dispersion (Mk-scaled, lower = tighter)
var module_primary_mount: bool = false
var module_primary_traverse: float = 0.0
var module_primary_dispersion: float = 0.0
var _blaster_aim: float = 0.0                # current blaster turret aim (rad, 0 = up)
var _primary_aim: float = 0.0                # current primary turret aim (rad, 0 = up)
var _blaster_cd_t: float = 0.0               # blaster direct-spawn cooldown countdown
var _primary_mount_ready: bool = true        # regen-laser latch: fire a full magazine, then wait for full recharge
var _blaster_bullet_scene: PackedScene = null  # cached blaster (cannon_pool[0]) fire config
var _blaster_damage: int = 1
var _blaster_cooldown: float = 0.2
var _blaster_sfx_kind: int = WS.FireSfxKind.BLASTER_SMALL  # blaster's OWN fire sound (fire_sfx_kind holds the primary's while it's loaded)

# Sector Conditions — cached player-kit multipliers (Weak/Better/Faster Weapons). Refreshed
# in apply_run_upgrades() (the combat-init choke, called from start() before the first shot).
# Default 1.0 keeps every effect site a strict no-op when no Condition is active.
var _cond_wpn_dmg_mult: float = 1.0    # player.weapon_damage_mult (Weak/Better Weapons)
var _cond_fire_rate_mult: float = 1.0  # player.fire_rate_mult (Faster Weapons)


# Sector Conditions weapon-damage CHOKE POINT (design §8): scale the FINAL per-shot
# damage at every player armament's damage-write site. One helper, N one-line call swaps —
# never scale the source vars (bullet_damage / _blaster_damage / secondary_damage /
# drone_bits_damage are rebuilt on equip and would double-scale). Rounded, floored at 1.
func _wpn_dmg(base: int) -> int:
	return maxi(1, roundi(base * _cond_wpn_dmg_mult))


# Effective secondary cooldown — Faster Weapons shortens the shared _secondary_t re-arm
# cadence. Reads the cached mult so the whole fire-gate machinery (cap / ready-gate /
# carry-subtract) stays consistent; identity when no Condition is active.
func _eff_secondary_cd() -> float:
	return secondary_cooldown / _cond_fire_rate_mult if _cond_fire_rate_mult != 1.0 else secondary_cooldown


# Faster Weapons for the burst-fire Rocket Pod (secondary_mode == BURST) — the 4th
# cadence path. Shortens both the intra-cycle rocket spacing and the post-cycle
# lockout, applied at CONSUMPTION time in _tick_burst (never at part-apply). Reads
# the cached mult so it stays consistent with _eff_secondary_cd; identity at 1.0.
func _eff_burst_interval() -> float:
	return secondary_burst_interval / _cond_fire_rate_mult if _cond_fire_rate_mult != 1.0 else secondary_burst_interval


func _eff_burst_cooldown() -> float:
	return secondary_burst_cooldown / _cond_fire_rate_mult if _cond_fire_rate_mult != 1.0 else secondary_burst_cooldown
var _mounts_enabled: bool = true             # runtime on/off (S toggle); off = manual control
var _mount_sight: Line2D = null              # teal aiming sight line (lazy-built)
const MOUNT_SIGHT_COLOR := Color(0.2, 1.0, 0.7, 0.85)  # teal-green
# Tunable turret geometry (the Smart Mount Lab pokes these live; defaults ship in combat).
var mount_arc: float = 1.0471975512          # ±60° = 120° front arc (deg_to_rad(60))
var mount_range: float = 240.0               # px target-acquisition radius
var mount_fire_tolerance: float = 0.1396263402  # fire when aim is within ~8° of the target bearing


# Critical System De-Limiter — fire-rate + damage bonus that scales up as hull drops,
# peaking at 1 hull (the "de-limiter" engaging under critical damage). 0 at full hull.
func _delimiter_bonus() -> float:
	if module_delimiter_max <= 0.0 or max_hull <= 1:
		return 0.0
	var frac: float = clampf(float(max_hull - hull) / float(max_hull - 1), 0.0, 1.0)
	return module_delimiter_max * frac


# Cached Run autoload for hot-path stat tallies (run-summary Phase 2) — avoids a
# per-shot get_node lookup. Run is an autoload, never freed during a session.
var _run_cache: Node = null
func _run_ref() -> Node:
	if _run_cache == null and has_node("/root/Run"):
		_run_cache = get_node("/root/Run")
	return _run_cache


func fire_primary(aim_angle: float = 0.0) -> void:
	# Minigun is now projectile-based (Roman 2026-06-11) — fires bullet_minigun
	# through the normal path below, like the other cannons.
	# aim_angle (rad, 0 = straight up) offsets every bolt's direction — the Primary
	# Smart Mount passes the turret bearing so the pipeline fires toward the target.
	if not can_shoot:
		return
	# Pulse Laser is HITSCAN (no bullet scene) — it bypasses the bullet-spawn path.
	var _is_pulse: bool = weapon_style == WS.WeaponStyle.PULSE_LASER
	if bullet_scene == null and not _is_pulse:
		return
	if _phase_on():
		return  # phased out — no offense
	# Metered primary out of ammo. Single-active model (2026-06-11): a REGEN
	# cannon (laser: ammo_recharge_rate > 0) just can't fire until it recharges —
	# it must NOT revert (there's no Q-cycle to get back). A NON-regen cannon
	# (minigun) reverts to an owned blaster. Hyper grants unlimited ammo, so a
	# dry metered weapon keeps firing while Hyper is active.
	if _is_replacement_primary_active() and ammo == 0 \
			and not (_hyper_on()):
		if ammo_recharge_rate > 0.0:
			return  # regen cannon: pause until it recharges, stay equipped
		# Smart Mount: a turreted primary stands down dry and waits — never falls back to
		# the blaster (Roman 2026-06-14). Otherwise the normal snap applies.
		if _mounts_active() and module_primary_mount:
			return
		_snap_to_blaster_and_reapply()
		return
	# Rotary Laser: also charge-gated.
	if weapon_style == WS.WeaponStyle.ROTARY_LASER and not _rl_charged:
		return
	can_shoot = false
	_echo_fired_this_frame = true   # Echo ghost re-fires this shot, delayed
	# Run-summary Phase 2: this is the fire COMMIT (a shot is happening this frame).
	# Note the active weapon once here (covers the pulse + bullet paths); shots_fired is
	# counted PER-PROJECTILE below (Quad/spread spawn N bolts per trigger).
	var _rs := _run_ref()
	if _rs != null:
		var _ac = _rs.get_active_cannon()
		if _ac != null and "display_name" in _ac:
			_rs.note_weapon_used(String(_ac.display_name))
	# Module bay — Targeting Computer: roll a crit ONCE per trigger (the whole volley
	# crits together for a readable purple burst). ×2 damage + purple bolt tint applied below.
	# Crit chance = Targeting Computer module + Focus mode (additive stack) while Focus is live.
	var _eff_crit: float = module_crit_chance + (focus_crit_chance if _focus_on() else 0.0)
	var _crit_shot: bool = _eff_crit > 0.0 and randf() < _eff_crit
	# Fire-rate bonuses (shorter cooldown), stacked additively: Refire mode + Overclock Core
	# (sustained-fire ramp) + Critical System De-Limiter (scales with hull lost). (Hyper no
	# longer boosts fire-rate — it's autofire-all now; Refire owns the cadence buff.)
	var _fire_bonus: float = 0.0
	if _refire_on() and refire_fire_bonus > 0.0:
		_fire_bonus += refire_fire_bonus
	if module_overclock_max > 0.0:
		_overclock_ramp = minf(1.0, _overclock_ramp + OVERCLOCK_RAMP_PER_SHOT)
		_overclock_idle_t = 0.0
		_fire_bonus += _overclock_ramp * module_overclock_max
	_fire_bonus += _delimiter_bonus()
	# Sector Conditions — Faster Weapons fold into the same fire-rate bonus sum so the
	# _eff_cd = cooldown / (1 + _fire_bonus) below picks it up (sub-frame carry preserved).
	# (mult 1.0 → adds 0.0, strict no-op.)
	_fire_bonus += (_cond_fire_rate_mult - 1.0)
	# Add this cycle's interval to the carried (negative) remainder so the previous
	# shot's sub-frame overshoot self-corrects — the average rate matches `cooldown`
	# instead of rounding each interval up to the next whole frame. The fire-rate
	# bonus (Refire / Overclock / De-Limiter) shortens ONLY this cycle; because the
	# interval is recomputed from `cooldown` every shot it can't compound or stick
	# after the bonus ends. (can_shoot was already cleared above.)
	# Sub-frame spawn (see _subframe_advance): how late this shot is vs its ideal
	# moment — the residual the carry banked. _gun_cd_t sits in [-FIRE_CARRY, 0] here,
	# so capture it BEFORE the += below turns it positive.
	var _fire_late: float = clampf(-_gun_cd_t, 0.0, FIRE_CARRY)
	var _eff_cd: float = cooldown
	if _fire_bonus > 0.0:
		_eff_cd = cooldown / (1.0 + _fire_bonus)
	_gun_cd_t += _eff_cd
	# Pulse Laser: hitscan beam from the nose, consume one ammo, then bail (no bullet
	# spawn). It's a metered REGEN laser, so when dry it PAUSES + recharges (the ammo==0
	# gate above) rather than snapping to the blaster — hence no _snap call here. Hyper
	# grants unlimited ammo. (Reaching here means the ammo gate already passed: ammo>0.)
	if _is_pulse:
		_fire_pulse_laser()
		if _rs != null:
			_rs.stat_add("shots_fired", 1)   # one hitscan beam = one shot
		if _is_replacement_primary_active() and ammo > 0 \
				and not (_hyper_on()):
			ammo -= 1
			ammo_changed.emit(ammo)
			if has_node("/root/Run"):
				var run = get_node("/root/Run")
				run.ammo = ammo
				var active = run.get_active_cannon()
				if active != null and "current_ammo" in active:
					active.current_ammo = ammo
		return
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
	# Quad Lasers fire one bolt per parallel x-offset (all straight up); otherwise
	# the spread-fan path (default 1 = single straight-up shot).
	var parallel: bool = primary_parallel_offsets.size() > 0
	var count: int = primary_parallel_offsets.size() if parallel else max(1, bullet_spread_count)
	if _rs != null:
		_rs.stat_add("shots_fired", count)   # per-projectile (Quad=4, spread fan=N, else 1)
	var spread_rad: float = deg_to_rad(bullet_spread_degrees)
	for i in range(count):
		var angle: float = 0.0
		if not parallel and count > 1:
			if bullet_spread_random:
				# Shotgun spread (Shredder): each pellet a RANDOM angle inside the cone,
				# not an even fan (Roman 2026-06-11).
				angle = randf_range(-spread_rad * 0.5, spread_rad * 0.5)
			else:
				var t: float = float(i) / float(count - 1)
				angle = -spread_rad * 0.5 + spread_rad * t
		# 0 angle = straight up. (sin(a), -cos(a)) rotates around the up axis.
		# aim_angle (Smart Mount turret bearing) rotates the whole volley toward the target.
		var dir := Vector2(sin(angle + aim_angle), -cos(angle + aim_angle))
		var b: Node = bullet_scene.instantiate()
		_bullet_parent().add_child(b)
		if b is Node2D:
			(b as Node2D).z_index = -1   # render under the player sprite (Roman 2026-06-09)
		# Propagate the equipped cannon's damage to the bullet so per-Part /
		# per-Mark scaling actually reaches the take_hit call.
		if "damage" in b:
			var dmg: int = bullet_damage
			# Module bay — Overcharge Core multiplies primary damage (1.0 = no module).
			if module_damage_mult != 1.0:
				dmg = int(round(float(dmg) * module_damage_mult))
			# Critical System De-Limiter: +damage scaling with hull lost (0 at full hull).
			var _delim: float = _delimiter_bonus()
			if _delim > 0.0:
				dmg = int(round(float(dmg) * (1.0 + _delim)))
			# Targeting Computer: a crit shot hits for ×2.
			if _crit_shot:
				dmg *= 2
			# Sector Conditions weapon-damage choke — scale the NET (post module/delimiter/crit).
			b.damage = _wpn_dmg(dmg)
		# Targeting Computer crit VFX — tint the bolt purple (HDR so the bloom glows it).
		if _crit_shot and b is CanvasItem:
			(b as CanvasItem).modulate = MODULE_CRIT_COLOR
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
		if parallel:
			# Quad Lasers: parallel bolt at muzzle + this (x,y) offset (muzzle flash stays centred).
			spawn_offset = muzzle_off + primary_parallel_offsets[i]
		elif fire_tandem_alternating and count == 1:
			# Auto Laser fires from the wing muzzle markers, alternating L/R.
			var wing: String = "Ship/MuzzleWingL" if _tandem_side == 0 else "Ship/MuzzleWingR"
			var fallback := Vector2(-4.0 if _tandem_side == 0 else 4.0, -2.0)
			spawn_offset = _muzzle_offset(wing, fallback)
			muzzle_pos = global_position + spawn_offset
			_tandem_side = 1 - _tandem_side
		elif primary_lateral_alternate > 0.0 and count == 1:
			# Twin Blaster: offset the Cannon marker ±N px laterally, alternating each shot.
			var dx: float = -primary_lateral_alternate if _tandem_side == 0 else primary_lateral_alternate
			spawn_offset = muzzle_off + Vector2(dx, 0.0)
			muzzle_pos = global_position + spawn_offset
			_tandem_side = 1 - _tandem_side
		# Velocity inheritance ("Doppler"): add the player's velocity along this bullet's
		# fire direction so flying toward the shots keeps the stream spacing constant
		# instead of bunching it. Forward component only (never negative) so descending
		# fast can't slow/reverse a slow bullet. Clamped to the clarity ceiling so a
		# boosted bullet can't strobe past 8 px/f (CLAUDE.md hard rule) when you fly up.
		if "speed" in b:
			b.speed = minf(b.speed + maxf(0.0, _move_velocity.dot(dir)), ClarityRules.ABS_MAX_SPEED)
		# Advance the spawn by the sub-frame lateness (uses the Doppler-adjusted speed above).
		b.start(position + spawn_offset + _subframe_advance(b, dir, _fire_late), dir)
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
					db.damage = _wpn_dmg(drone_bits_damage)
				db.start(drone.global_position + Vector2(0, -4))
	# Unified player muzzle flash (Roman 2026-06-09): bottom-anchored, ~1 frame, diffuse glow,
	# above the bullets. Colour rules: Auto Laser + Rotary = pure blue; MG family (machinegun,
	# autocannon, minigun) = bright orange; everything else = the engine glow colour.
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	var flash_color: Color = ENGINE_GLOW_COLOR
	if weapon_style == WS.WeaponStyle.ROTARY_LASER or use_rotary_laser_muzzle:
		flash_color = Color(0.2, 0.45, 1.0)        # pure blue
	elif _is_mg_family(weapon_style) or use_autocannon_muzzle:
		flash_color = Color(1.0, 0.5, 0.1)         # bright orange (cannon)
	# Shell casing size: legacy Machinegun uses the LARGE casing; the Autocannon is back
	# on the SMALL casing (Roman 2026-06-11). Minigun ejects a brass PIXEL (+ thin smoke
	# trail) instead of a casing — so it skips the shell+smoke, then ejects brass below.
	# The Shredder (use_autocannon_muzzle) rides the autocannon's small-shell + smoke look.
	var _large_shell: bool = weapon_style == WS.WeaponStyle.MACHINEGUN
	var _is_minigun: bool = weapon_style == WS.WeaponStyle.MINIGUN
	var _smoke_shell: bool = (_is_mg_family(weapon_style) and not _is_minigun) or use_autocannon_muzzle
	# Smart Mount: rotate the muzzle position + flash around the ship center by the turret
	# bearing (aim_angle); 0 (manual / mount off) = the normal axial nose flash.
	var _flash_pos: Vector2 = global_position + (muzzle_pos - global_position).rotated(aim_angle)
	MuzzleFx.play_player(_flash_pos, self, flash_color, _smoke_shell, _large_shell, false, 6, aim_angle)
	if _is_minigun:
		var _fx_parent: Node = get_parent() if get_parent() != null else get_tree().root
		# Casings eject from the ship's casing-eject marker (Roman 2026-06-11).
		var eject_off: Vector2 = _muzzle_offset("Ship/Muzzle/Gun_Nose_Eject", Vector2(1.0, -5.0))
		MuzzleFx.eject_brass(_fx_parent, global_position + eject_off)
	# Per-shot cannon SFX. Excluded styles carry their OWN audio elsewhere: MACHINEGUN = the
	# _mg_loop_player loop, ROTARY_LASER = the per-shot pew system. MINIGUN now fires projectiles
	# through this path, so its MINIGUN_CLIPS play per shot via fire_sfx_kind (Roman 2026-06-11).
	# AUTOCANNON falls through here too — its autocannon_shoot_* clips play per shot.
	if weapon_style != WS.WeaponStyle.MACHINEGUN \
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
			and not (_hyper_on()):
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


# True when the active primary is a METERED cannon (carries ammo). Infinite
# blasters (Energy/Heavy/Twin) seed ammo_max = -1. Single-active model
# (2026-06-11): the discriminator is "does it meter ammo", not the pool index.
func _is_replacement_primary_active() -> bool:
	return ammo_max > 0


# Set the firing cannon to the Blaster (slot 0) and re-apply it through the
# loadout so bullet_scene / cooldown / damage / SFX revert. Called when a
# non-regen Primary runs dry — the Primary STAYS equipped in slot 1 (refill +
# Q back). Two-slot model (2026-06-11).
func _snap_to_blaster_and_reapply() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	run.swap_to_blaster()
	_reapply_active_cannon()


# Q toggle: switch the firing cannon between the Blaster and the Primary. No-op
# when only the Blaster is equipped.
func _swap_active_primary() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.cannon_pool.size()) <= 1:
		return
	run.cycle_primary()
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

# Small warm launch flash for secondary weapons (missiles / rockets / pods), which
# previously fired with NO muzzle flash (Roman 2026-06-11: "muzzleflashes missing
# from most weapons"). No smoke/shell — secondaries are launches, not gun fire.
func _secondary_muzzle(world_pos: Vector2) -> void:
	var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
	if MuzzleFx:
		# flip_v + z=-3: the launch flash points the other way and renders UNDER the
		# player, matching the wing-launched secondaries (Roman 2026-06-11).
		MuzzleFx.play_player(world_pos, self, Color(1.0, 0.8, 0.4), false, false, true, -3)


func fire_secondary() -> void:
	# HARDPOINT_WING Parts (Seeking Missile, Rocket Pod, Side Pods) write
	# to secondary_bullet_scene / cooldown / damage / pod_count in their
	# apply(). One cooldown tick spawns secondary_pod_count bullets
	# evenly distributed across ±halfspan.
	if secondary_bullet_scene == null:
		return
	if not is_alive:
		return
	if _secondary_t < _eff_secondary_cd():
		return
	# Ammo gate — only applies to metered secondaries (Rocket Pod / Seeking
	# Missile set secondary_ammo_max > 0). Unmetered (-1) fires forever. Hyper grants
	# free secondary fire, so a dry metered secondary still launches while Hyper is active.
	if secondary_ammo == 0 and not _hyper_on():
		return
	_secondary_t -= _eff_secondary_cd()  # carry the sub-frame overshoot, don't zero
	var count: int = max(1, secondary_pod_count)
	var _rs_sec := _run_ref()
	if _rs_sec != null:
		_rs_sec.stat_add("shots_fired", count)   # secondary projectiles (deploy mode returned above)
	for i in count:
		var offset_x: float = 0.0
		if count > 1:
			# Spread evenly from -halfspan to +halfspan.
			var t: float = float(i) / float(count - 1)
			offset_x = -secondary_pod_halfspan + secondary_pod_halfspan * 2.0 * t
		var b: Node = secondary_bullet_scene.instantiate()
		_bullet_parent().add_child(b)
		if "damage" in b:
			b.damage = _wpn_dmg(secondary_damage)
		if secondary_homing and "guided" in b:
			b.guided = true
		# Single-missile secondaries (seeker / anti-ship) launch from the wing markers,
		# alternating L/R. Multi-pod (Side Pods) keep their fanned offsets.
		if count == 1:
			var wing: String = "Ship/LaunchWingL" if _secondary_wing == 0 else "Ship/LaunchWingR"
			var fallback := Vector2(-6.0 if _secondary_wing == 0 else 6.0, 1.0)
			var sp1: Vector2 = _muzzle_offset(wing, fallback)
			b.start(position + sp1)
			_secondary_muzzle(global_position + sp1)
			_secondary_wing = 1 - _secondary_wing
		else:
			var sp2 := Vector2(offset_x, -10)
			b.start(position + sp2)
			_secondary_muzzle(global_position + sp2)
	var WeaponSfxSec = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfxSec:
		var kind: String = "missile" if secondary_homing else "rocket"
		WeaponSfxSec.play(get_tree().root, global_position, kind)
	# Decrement ONE per fire_secondary press regardless of pod_count — the
	# pod_count is a visual fan, not a per-shot multiplier on ammo cost.
	# (If we ever want pod_count to cost N rounds, change here.)
	if secondary_ammo > 0 and not _hyper_on():
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
				_burst_shot_t += _eff_burst_interval()  # Faster Weapons: shorten rocket spacing
			if _burst_shots_left <= 0:
				_burst_phase = 2
				_burst_cool_t = _eff_burst_cooldown()  # Faster Weapons: shorten cycle lockout
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
		b.damage_on_contact = _wpn_dmg(secondary_damage)
	if "damage" in b:
		b.damage = _wpn_dmg(secondary_damage)
	var sp_burst: Vector2 = _muzzle_offset(wing, fallback)
	b.start(position + sp_burst)
	_secondary_muzzle(global_position + sp_burst)
	var WeaponSfxBurst = load("res://scripts/effects/weapon_sfx.gd")
	if WeaponSfxBurst:
		WeaponSfxBurst.play(get_tree().root, global_position, "rocket")
	# One round per rocket (per-rocket ammo cost).
	if secondary_ammo > 0 and not _hyper_on():
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
	# Prune freed drones from the tracking list (each drone self-expires + blue-disintegrates on its own
	# 30s timer now — the wave is no longer player-timed).
	for i in range(_deployed_drones.size() - 1, -1, -1):
		if not is_instance_valid(_deployed_drones[i]):
			_deployed_drones.remove_at(i)
	# Combat Drones REBUILD (Roman 2026-07-08): DRONE-owned lifetime, so there's no wave gate or deploy
	# timer — every shoot2 press spends 1 ammo and spawns another wave while ammo remains; waves overlap.
	# The HUD stays on the ammo count (no secondary_timer emitted).
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
	_deployed_drones.append_array(spawned)
	# Consume one ammo.
	if secondary_ammo > 0 and not _hyper_on():
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
	if not is_alive or _phase_on():
		return
	if not Input.is_action_just_pressed("shoot2"):
		return
	if secondary_ammo == 0:
		return
	if _secondary_t < _eff_secondary_cd():
		return  # still cooling down
	var part = _secondary_part()
	if part == null or not part.has_method("fire_salvo"):
		return
	if not part.fire_salvo(self):
		return
	_secondary_muzzle(global_position + _muzzle_offset("Ship/Muzzle", Vector2(0, -8)))
	_secondary_t -= _eff_secondary_cd()  # restart, carrying the sub-frame overshoot
	if secondary_ammo > 0 and not _hyper_on():
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
	# Particle Beam is a player armament — Sector Conditions weapon-damage choke applies to its
	# per-tick DPS too (identity when no Condition is active).
	var dmg_amount: int = _wpn_dmg(max(1, int(round(secondary_beam_dps * delta))))
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
		# A single CENTRAL pixel (Roman 2026-06-11: 1px, not 2x2), bright teal.
		dot.size = Vector2(1, 1)
		dot.position = Vector2(-0.5, -0.5)
		dot.color = FOCUS_DOT_COLOR
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_dot.add_child(dot)
		_focus_dot.z_index = 100
		add_child(_focus_dot)
	_focus_dot.visible = visible
	# Edge-triggered sound + glow aura + doubled exhaust + the REAL hitbox swap.
	# Create-once on enter, free/restore on exit — no per-frame node churn.
	if visible and not _focus_was_active:
		_play_focus_sound(true)
		_focus_visuals_enter()
		_set_focus_hitbox(true)
	elif not visible and _focus_was_active:
		_play_focus_sound(false)
		_focus_visuals_exit()
		_set_focus_hitbox(false)
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
			_focus_trail.width = 1.0   # thin (Roman 2026-06-11)
			_focus_trail.joint_mode = Line2D.LINE_JOINT_ROUND
			_focus_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
			_focus_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
			_focus_trail.z_index = 99
			# Same bright teal as the dot, fading to transparent at the tail.
			var grad := Gradient.new()
			grad.set_color(0, Color(FOCUS_DOT_COLOR.r, FOCUS_DOT_COLOR.g, FOCUS_DOT_COLOR.b, 0.0))
			grad.set_color(1, Color(FOCUS_DOT_COLOR.r, FOCUS_DOT_COLOR.g, FOCUS_DOT_COLOR.b, 0.85))
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


# Swap the player's collider while focused: disable the full ship hitbox and enable
# a 1px CENTRAL one (Touhou-style focus). Deferred — a collider's `disabled` can't
# change mid-physics-callback. Restored on focus release. (Roman 2026-06-11.)
func _set_focus_hitbox(active: bool) -> void:
	if _focus_hitbox == null:
		_focus_hitbox = CollisionShape2D.new()
		_focus_hitbox.name = "FocusHitbox"
		var r := RectangleShape2D.new()
		r.size = Vector2(1, 1)   # 1px, centred on the ship origin
		_focus_hitbox.shape = r
		_focus_hitbox.disabled = true
		add_child(_focus_hitbox)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", active)
	_focus_hitbox.set_deferred("disabled", not active)


# Focus-enter: spawn the diffuse glow aura behind the ship sprite and double
# the engine exhaust length. Guarded against double-spawn so a stray re-entry
# never leaks a second glow node.
func _focus_visuals_enter() -> void:
	if not has_node("Ship"):
		return
	# Soft cyan radial bloom behind the ship (GlowFx.attach_glow childs an additive
	# halo at z_index -1). Returns a Sprite2D, held as CanvasItem.
	if _focus_glow == null or not is_instance_valid(_focus_glow):
		_focus_glow = GlowFx.attach_glow($Ship, FOCUS_GLOW_COLOR, 1.6, 0.7)


# Focus-exit: free the glow aura.
func _focus_visuals_exit() -> void:
	if _focus_glow != null and is_instance_valid(_focus_glow):
		_focus_glow.queue_free()
	_focus_glow = null


func _play_focus_sound(_starting: bool) -> void:
	pass  # TODO: swap in focus_start.wav / focus_end.wav when assets land

func _on_gun_cooldown_timeout() -> void:
	# Vestigial: GunCooldown/MinigunCooldown are no longer started — fire readiness is
	# driven by _gun_cd_t in _process (see its decl). Kept because the scene still wires
	# these Timers' timeout signals here; harmless if one ever fires.
	can_shoot = true

func _on_area_entered(area: Area2D) -> void:
	# Flat 1 for EVERY source (ship contact, mines, missiles/rockets tagged "enemies", and
	# bullets). take_damage() normalizes to 1 regardless, so these literals are kept at 1 only
	# for honesty. take_hit(6) is the player's ram damage TO the enemy — unrelated to what the
	# player takes. (Roman 2026-07-04: damage is flat; difficulty scales via volume.)
	if area.is_in_group("enemies"):
		if "ram" in area and area.ram:
			# Ram enemy: it barrels through (takes NO contact damage) and knocks the player back
			# asteroid-style. The player still takes the flat 1. (Bullets still hurt a ram enemy.)
			_ram_knockback(area)
		elif area.has_method("take_hit"):
			area.take_hit(6)   # player rams a normal enemy for 6
		_play_hit_sfx()
		take_damage(1)
	elif area.is_in_group("bullets"):
		_play_hit_sfx()
		take_damage(1)


# Asteroid-style billiards shove AWAY from a ram enemy on contact (mirrors asteroid.gd's PLAYER_KICK
# tween). Grace-gated so successive rams don't pinball the player. The per-frame Playfield clamp in
# _process keeps the tweened position in-band.
func _ram_knockback(enemy) -> void:
	if not (enemy is Node2D):
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_ram_kick_ms < RAM_KICK_GRACE_MS:
		return
	_last_ram_kick_ms = now
	var away: Vector2 = global_position - (enemy as Node2D).global_position
	away = away.normalized() if away.length() > 1.0 else Vector2(randf_range(-1.0, 1.0), -0.5).normalized()
	var tw := create_tween()
	tw.tween_property(self, "position", position + away * RAM_KICK, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# External pull (Roman 2026-07-06, spring rework 2026-07-07) — a leash/tractor drag applied by another
# entity (the Abductor's grab beam). Keeps player-motion authority player-side (mirrors _ram_knockback).
# Instead of a rigid position-lerp, the caller hands us a WORLD-SPACE anchor it wants to reel us toward
# (the leash edge). We run a critically-ish-damped SPRING against a persistent `_pull_velocity`, so the
# ship is smoothly ACCELERATED toward the anchor and carries momentum (it feels like mass) rather than
# snapping. `strength` scales the spring pull, `damping` bleeds velocity (higher = less overshoot),
# `max_speed` caps how fast the tractor can haul us. The integrated step is re-clamped to the playfield
# band so the drag can never haul the ship out of bounds.
const PULL_SPRING_DEFAULT: float = 14.0     # spring stiffness (accel toward anchor per px of error)
const PULL_DAMPING_DEFAULT: float = 6.0     # velocity bleed per second (higher = calmer, less overshoot)
const PULL_MAX_SPEED_DEFAULT: float = 260.0 # px/s ceiling on the tractor drag
const PULL_VELOCITY_DECAY: float = 8.0      # per-second decay applied to residual pull velocity when idle
var _pull_velocity: Vector2 = Vector2.ZERO
var _pull_active_frame: bool = false        # set true by apply_external_pull, consumed in _process

func apply_external_pull(anchor: Vector2, delta: float, strength: float = PULL_SPRING_DEFAULT, damping: float = PULL_DAMPING_DEFAULT, max_speed: float = PULL_MAX_SPEED_DEFAULT) -> void:
	if delta <= 0.0:
		return
	var step: float = minf(delta, 1.0 / 30.0)   # match the movement delta cap so a hitch can't teleport
	var error: Vector2 = anchor - global_position
	# Spring accel toward the anchor, exponential velocity damping (frame-rate independent).
	_pull_velocity += error * strength * step
	_pull_velocity *= exp(-damping * step)
	if _pull_velocity.length() > max_speed:
		_pull_velocity = _pull_velocity.normalized() * max_speed
	position += _pull_velocity * step
	position = Playfield.clamp_pos(position, 8.0)
	_pull_active_frame = true


# Called each _process frame to bleed off residual tractor momentum once the beam stops pulling, so the
# ship doesn't keep coasting after release. When actively pulled the flag is set fresh each frame.
func _decay_pull_velocity(delta: float) -> void:
	if _pull_active_frame:
		_pull_active_frame = false
		return
	if _pull_velocity == Vector2.ZERO:
		return
	_pull_velocity *= exp(-PULL_VELOCITY_DECAY * delta)
	if _pull_velocity.length() < 1.0:
		_pull_velocity = Vector2.ZERO


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


# Passive Energy Routers (module): while the trigger has been idle past the grace
# window, shield regen kicks in sooner AND ticks faster — delay/interval scaled down
# by module_energy_router_pct. No module / actively firing = the plain values (which
# the Shield Capacitor may already have lowered).
func _is_weapon_idle() -> bool:
	return _shot_recency >= ROUTER_IDLE_GRACE

func _effective_regen_delay() -> float:
	var d: float = shield_regen_delay
	if module_energy_router_pct > 0.0 and _is_weapon_idle():
		d = maxf(0.1, shield_regen_delay * (1.0 - module_energy_router_pct))
	# Sector Conditions — Better Shields shorten the recharge delay; composes with the
	# module-adjusted value, floored at 1.0s. Identity (no floor) when no Condition set it.
	var run = _run_ref()
	if run != null:
		var m: float = run.cond_scalar("player.shield_regen_delay_mult")
		if m != 1.0:
			d = maxf(1.0, d * m)
	return d

func _effective_regen_interval() -> float:
	var iv: float = shield_regen_interval
	if module_energy_router_pct > 0.0 and _is_weapon_idle():
		iv = maxf(0.1, shield_regen_interval * (1.0 - module_energy_router_pct))
	# Sector Conditions — Better Shields speed up the regen ticks; composes with the
	# module-adjusted value, floored at 0.25s. Identity when no Condition set it.
	var run = _run_ref()
	if run != null:
		var m: float = run.cond_scalar("player.shield_regen_rate_mult")
		if m != 1.0:
			iv = maxf(0.25, iv / m)
	return iv


func _on_shield_regen_timer_timeout() -> void:
	if _shield_in_delay:
		# 5s delay just expired — begin 1/sec regen ticks.
		_shield_in_delay = false
		if shield < max_shield:
			$ShieldRegenTimer.wait_time = _effective_regen_interval()  # Capacitor + Energy Routers lower this
			$ShieldRegenTimer.start()
		return
	# Regen tick: +1 charge per interval (shield_regen_interval; default 1s).
	if shield < max_shield:
		set_shield(shield + 1)
		_pulse_shield_ring()   # per-charge regen pulse (reuses the hit ripple)
		# Energy Routers: re-evaluate the interval each tick so the regen RATE tracks
		# the trigger — speeds up while idle, slows the moment you open fire.
		var iv: float = _effective_regen_interval()
		if not is_equal_approx($ShieldRegenTimer.wait_time, iv):
			$ShieldRegenTimer.wait_time = iv


# Translate the module bay + (legacy) Run upgrades into runtime stats. Called from
# start() so every combat scene picks up the latest values. Hull / Thrusters / Shield
# Capacity are now MODULES (2026-06-13): their contribution is read off the module_*
# ship fields the module apply loop set in _ready, NOT Run ints.
#   Hull            base 2 + Reinforced Hull module pips; its Mk.9 = repair −30%
#   Thrusters       +speed % from the Thrusters module
#   Shield          base 10 + Shield Core Mk capacity − Overcharge penalty, gated on the Core
#   Armor / shield-recharge / self-repair / hull-plating upgrades RETIRED (save-compat fields only)
func apply_run_upgrades() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Sector Conditions — refresh the cached player-kit multipliers before the first shot
	# (this is the combat-init choke). Null-safe defaults keep everything a no-op when
	# active_conditions is empty.
	_cond_wpn_dmg_mult = run.cond_scalar("player.weapon_damage_mult")
	_cond_fire_rate_mult = run.cond_scalar("player.fire_rate_mult")
	# Hull: 2 base + the Reinforced Hull module's pips. (Its Mk.9 repair discount is
	# read by the outpost via Run.hull_repair_discount() — repairs happen there, not here.)
	max_hull = 2 + module_hull_bonus
	# Sector Conditions — Better Hull adds flat pips on top of the module hull.
	max_hull += int(run.cond_sum("player.hull_bonus"))
	hull_shrug_chance = 0.0  # the RNG shrug is the Ablative Plating module now (module_ablative_n)
	# Speed: baseline + the Thrusters module's bonus.
	speed_multiplier = max(0.3, 1.0 + module_speed_pct)
	# Shield: base 10 + the Shield Core's Mk capacity (module_shield_bonus) − Overcharge's
	# charge penalty, then the glass-cannon gate (initialized bay + no Shield Core = no shield).
	max_shield = 10 + module_shield_bonus - module_shield_charge_penalty
	if bool(run.get("bay_initialized")) and not run.has_module("shield_core"):
		max_shield = 0
	max_shield = maxi(0, max_shield)
	# Sector Conditions — Weak/Better Shields scale the whole assembled charge pool, but
	# only when a shield actually exists (respect the shieldless gate above). Weak Shields'
	# "half now + half per progression" falls out of scaling the module-assembled pool.
	if max_shield > 0:
		max_shield = maxi(1, roundi(max_shield * run.cond_scalar("player.shield_charges_mult")))
	# shield_recharge_mk retired — regen is now always 1/sec after 5s delay.
	# Re-emit so the damage tells (fire/smoke) re-evaluate their activation FRACTION
	# (1 - hull/max_hull) against the NEW max_hull whenever upgrades change it — not just
	# in start()'s emit (Roman 2026-06-11: max-hp changes weren't being picked up).
	hull_changed.emit(max_hull, hull)


# Self Repair heal moved to sector_map_v3 return (spec 2026-05-26).
# This function is kept as a no-op stub so any lingering call sites don't crash.
func _self_repair_amount() -> int:
	return 0


# ---- Shield ring helpers (thin wrappers over the shared ShieldRingFx driver) ----
# Collapse (fade opacity + shrink size to 0) or come online (reverse). `target` is the old
# alpha convention: > 0 = online, 0 = offline.
func _set_shield_ring_alpha(target: float, duration: float) -> void:
	if _shield_fx != null:
		_shield_fx.set_online(target > 0.0, duration)

# The hit_strength ripple pulse — reused for shield regen (per recovered charge) + bullet-steal.
func _pulse_shield_ring() -> void:
	if _shield_fx != null:
		_shield_fx.pulse()

# fill_alpha + flicker track the current shield fraction (full → bold/steady, empty → faint/flickering).
func _apply_shield_state() -> void:
	if _shield_fx != null:
		_shield_fx.apply_state(float(shield) / float(maxi(1, max_shield)))

# Shield-absorbed hit: bright white flash held through the i-frame, then resettle to base + state.
func _flash_shield_ring() -> void:
	if _shield_fx != null:
		_shield_fx.hit_flash(float(shield) / float(maxi(1, max_shield)), SHIELD_HIT_INVULN_SECONDS)


# Brief on-screen toast announcing the new autofire state. Mounts a
# CanvasLayer above the HUD (layer 20) so it sits over gameplay AND the
# side gutters; auto-frees after ~1s. Stacked invocations replace the
# prior toast rather than piling up.
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
var _autofire_toast: CanvasLayer = null

func _show_autofire_toast(on: bool) -> void:
	_show_center_toast("AUTOFIRE: ON" if on else "AUTOFIRE: OFF")


func _show_mount_toast(on: bool) -> void:
	_show_center_toast("SMART MOUNT: ON" if on else "SMART MOUNT: OFF")


# Brief center-top toast (autofire / smart-mount toggles share the one slot).
func _show_center_toast(text: String) -> void:
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
	lbl.text = text
	UiTheme.style_label(lbl, UiTheme.LabelKind.HEADER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	# Drop the label a bit below the top edge so it doesn't clip against
	# the playfield outline. PRESET_CENTER_TOP anchors at y=0; nudge down.
	lbl.position = Vector2(-90, 16)
	lbl.size = Vector2(180, 16)
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
