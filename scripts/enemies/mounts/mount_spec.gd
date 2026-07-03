extends Resource

# MountSpec (Roman 2026-06-16) — data describing ONE additional firing emitter on an enemy: which
# marker it fires from, what KIND of emitter, what it shoots (payload), and its cadence/aim/spread.
# A shared model that BOTH the Enemy Bench AND production (roster "mounts" -> EnemyRoster.make_mounts
# -> director) consume. Realized at spawn by MountBuilder into the matching primitive:
#   GUN/LAUNCHER -> a MountComponent (own fire timer)   TURRET -> an EnemyTurret   BEAM -> a BeamEmitter
#
# Mounts COMPLEMENT the hull `shoot_pattern` (which stays the primary weapon, timed by enemy_core);
# they are the EXTRA guns/turrets/launchers/beams that used to be hardcoded in bespoke scripts.
#
# Preload-const, NOT class_name (a fresh class_name doesn't resolve under headless --script until the
# cache regenerates — the firing-resource convention, see weapon.gd / movement_pattern.gd).

enum Kind { GUN, TURRET, LAUNCHER, BEAM }
enum Aim { STRAIGHT_DOWN, TOWARD_CENTER, AT_PLAYER, FORWARD, BACKWARD, LEFT, RIGHT }   # mirrors Weapon.Aim (int values MUST stay in lockstep)
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

# --- BEAM only (a BeamEmitter.configure() dict) ---
@export var beam_config: Dictionary = {}
