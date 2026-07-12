extends Resource

# MountSpec (Roman 2026-06-16) — data describing ONE additional firing emitter on an enemy: which
# marker it fires from, what KIND of emitter, what it shoots (payload), and its cadence/aim/spread.
# A shared model that BOTH the Enemy Bench AND production (roster "mounts" -> EnemyRoster.make_mounts
# -> director) consume. Realized at spawn by MountBuilder into the matching primitive:
#   GUN/LAUNCHER -> a MountComponent (own fire timer)   TURRET -> an EnemyTurret   BEAM -> a BeamEmitter
#
# The roster fires almost entirely through mounts — the enemy-firing→mount consolidation (2026-06-23)
# retired the old "Mount 0"/hull-weapon-only path, so mounts ARE the guns/turrets/launchers/beams. As of
# the firing-engine consolidation (2026-07-07) even a hull `shoot_pattern` is realized as a MountComponent
# (kind GUN, hull_pattern = the pattern) by enemy_core._realize_shoot_pattern_mount, so ONE engine (this
# spec's cadence/gate/path-phase/on-phase, ticked on FiringScheduler) drives every enemy weapon.
#
# Preload-const, NOT class_name (a fresh class_name doesn't resolve under headless --script until the
# cache regenerates — the firing-resource convention, see weapon.gd / movement_pattern.gd).

# ENTITY (Phase 2 unification 2026-07-03) — spawn a SCENE (mine/drone/bomblet/firecore) on a trigger,
# folding the old EmitterComponent into this one spec+component. GUN=bullet, LAUNCHER=aimed projectile,
# ENTITY=dropped/scattered scene. TURRET/BEAM stay separate node realizations the builder routes to.
# Hardpoint v2 Phase A (2026-07-05): the GUN vs LAUNCHER fire path is now chosen by PAYLOAD TYPE, not
# kind — a mount with a payload_scene takes the projectile path whatever its kind, so LAUNCHER is just a
# GUN carrying a payload_scene. Kept as a roster/bench alias (zero-churn), no longer its own fire branch.
enum Kind { GUN, TURRET, LAUNCHER, BEAM, ENTITY, RING }
# Aim is ALIASED to Weapon.Aim (not re-declared) so the two can never drift — the old manual mirror
# is now mechanical. Referenced as MountSpec.Aim exactly as before. Weapon.Aim stays the source of truth.
const _WeaponScript = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const Aim = _WeaponScript.Aim
# ALL = fire from every matched marker; CYCLE = one per volley (scene order). INWARD/OUTWARD =
# ordered cycle by horizontal distance from the hull centre — OUTWARD fires the outermost hardpoint
# first working in, INWARD the reverse (Roman 2026-07-03). Pair with burst_interval for a ripple.
enum MarkerMode { ALL, CYCLE, INWARD, OUTWARD }

@export var kind: int = Kind.GUN
@export var marker: String = ""                # exact name or glob ("Cannon*"); "" = hull centre
@export var marker_mode: int = MarkerMode.ALL
@export var payload: Resource = null           # BulletVariant (GUN / TURRET)
@export var payload_scene: PackedScene = null  # projectile scene (LAUNCHER) — wins over payload
@export var fire_interval_min: float = 2.0
@export var fire_interval_max: float = 2.0
@export var aim: int = Aim.STRAIGHT_DOWN
@export var lead_factor: float = 0.0
@export var bullet_speed: float = -1.0         # -1 = leave the variant's own speed
@export var count: int = 1                     # shots/rockets per volley
@export var spread_deg: float = 0.0            # fan across the volley
@export var burst_interval: float = 0.0        # >0 staggers the `count` shots in time
# "Drop" gun (Roman 2026-06-29): the shot ignores the enemy's velocity inheritance ("Doppler"), so it
# leaves at its OWN intended speed no matter how fast the gun is travelling — lets ANY payload be
# dropped without a bespoke slow bullet. false = normal inertia-carrying fire.
@export var no_inertia: bool = false
# Payload Delay (Roman 2026-07-03, off by default): the spawned payload holds at the muzzle for this
# many milliseconds before its motion begins, then travels normally. Set onto the bullet/projectile's
# `motion_delay` at spawn. 0 = fire immediately (unchanged).
@export var payload_delay_ms: float = 0.0
# Shot deviation (Roman 2026-07-04): random ± angle jitter (deg) applied to each shot's direction so a
# weapon can be inaccurate / spray. 0 = pinpoint (unchanged). Honoured by GUN/LAUNCHER/TURRET.
@export var deviation_deg: float = 0.0
# Fire cap per pass (Roman 2026-07-04): stop after this many GUN/LAUNCHER fires per parallax pass
# (mirrors ENTITY max_emits). 0 = unlimited.
@export var max_fires: int = 0
# Spread layers / volleys (Roman 2026-07-04): fire the whole count-shot fan `volleys` times, staggered
# by volley_gap seconds — so a 3-shot spread × 4 volleys = a 12-shot fan. 1 = a single volley (unchanged;
# burst_interval still staggers the shots WITHIN a volley).
@export var volleys: int = 1
@export var volley_gap: float = 0.0

# Projectile-movement axis driven onto each spawned bullet (mirrors Weapon).
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0

# --- Firing conditions (captured from enemy_core's hull shoot, 2026-06-23) so a GUN/LAUNCHER mount
# can fully replace a conditional hull weapon. GATES hold fire across the cadence; fire_path_phases
# swaps the cadence for fixed band-progress firing. Honoured by MountComponent (GUN/LAUNCHER); the
# TURRET arc-gate covers its own conditional fire. ---
@export var fire_zone_gated: bool = false       # only fire inside Zones.in_engagement (hold above, cease below)
@export var fire_only_on_target: bool = false   # only fire when the host nose points at the player
@export var fire_aim_tol_deg: float = 18.0      # nose-alignment tolerance for fire_only_on_target
@export var fire_path_phases: PackedFloat32Array = PackedFloat32Array()  # fire once past each band-progress fraction
@export var fire_beat_synced: bool = true       # quantize path-phase shots to the shared tempo (volley collapse)
@export var fire_on_phase: String = ""          # fire when the host movement enters this named phase (not cadence)

# --- TURRET only (forwarded 1:1 to EnemyTurret) ---
@export var rotation_speed: float = 3.6
@export var arc_deg: float = 0.0
@export var rest_angle_deg: float = 0.0
@export var arc_gate: bool = false
@export var lock_to_fire: bool = false
@export var lock_duration: float = 0.4
@export var aim_tolerance_deg: float = 14.0
@export var recoil_frames: int = 0
@export var turret_texture: Texture2D = null
@export var turret_hframes: int = 1
# Which hframe of turret_texture is the barrel art. Default 0 (turret sheets whose frame 0 IS the
# turret, e.g. the zealot tank-turret). Set >0 when the turret lives in a COMBINED base sheet where an
# earlier frame is the immobile platform (the core turret's enemy_turret_base.png: 0=base, 1=destroyed,
# 2=turret). Clamped to the strip in the builder. (Roman 2026-07-12.)
@export var turret_frame: int = 0

# --- BEAM only (a BeamEmitter.configure() dict) ---
@export var beam_config: Dictionary = {}

# --- ENTITY only (Phase 2, folds EmitterComponent) — spawn payload_scene on a trigger. CADENCE reuses
# fire_interval_min/max as the emit period; START emits once at spawn; DEATH emits on death by
# emit_chance. `count` = scenes per emit, `no_inertia` = drop-at-rest (true) vs launch-with-velocity
# (false), `payload_delay_ms` applies to the spawned scene, same as a bullet. ---
enum Trigger { CADENCE, START, DEATH }
@export var trigger: int = Trigger.CADENCE
@export var emit_scatter: float = 0.0        # px positional jitter around the origin
@export var emit_chance: float = 1.0         # probability per emit (DEATH scatter / chance-gated)
@export var max_emits: int = 0               # CADENCE: stop after this many emits per pass (0 = unlimited)
@export var band_only: bool = false          # CADENCE: only emit while on the visible playfield band
@export var attach_to_enemy: bool = false    # child of the enemy (carried turrets ride along)
@export var emit_tag: String = ""            # optional identifier (e.g. "firecore")
@export var emit_sfx: String = ""            # optional WeaponSfx key played on each emit

# --- RING only (Hardpoint v2 Phase C, 2026-07-05) — an OrbitComponent delivery: N rings of payloads
# orbit the host and are RELEASED on death/leave (folds firecore-bloom + cluster/gravity mines onto one
# path). MountBuilder realizes these into an OrbitComponent. Each ring dict = { radius, count, speed,
# variant (VISUAL BulletVariant), scene (LIVE payload), tex, scale, color }. See OrbitComponent. ---
@export var rings: Array = []                 # the ring specs (see OrbitComponent.rings)
@export var orbit_mode: int = 0               # 0 = VISUAL (bullet shells), 1 = LIVE (real payload scenes)
@export var release_speed: float = 140.0      # VISUAL: outward speed of released projectiles (px/s)
@export var host_drift: float = 0.0           # LIVE: host downward drift inherited on release (px/s)
@export var release_sfx: String = "enemy_blaster"
