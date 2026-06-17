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
enum Aim { STRAIGHT_DOWN, TOWARD_CENTER, AT_PLAYER, FORWARD }   # mirrors Weapon.Aim
enum MarkerMode { ALL, CYCLE }   # ALL = fire from every matched marker; CYCLE = one per volley

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

# Projectile-movement axis driven onto each spawned bullet (mirrors Weapon).
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0

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
