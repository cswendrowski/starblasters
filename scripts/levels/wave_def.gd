extends Resource

# One wave of enemies inside a Level.

# WALL/PINCER (2026-06-05): producer-requestable shaped formations. The conductor's
# wall machinery existed but was only reachable from hand-authored scores; these enum
# values let WaveGen tag fast-chaff waves so they arrive as readable walls (rows with
# 1-2 gap lanes) instead of a one-at-a-time spread trickle. See ScoreAdapter._shape_id
# + director._dispatch_wall.
enum Formation { TOP_LEFT_TO_RIGHT, TOP_RIGHT_TO_LEFT, TOP_RANDOM, TOP_CENTER_OUT, SIDE_ALTERNATING, TOP_TANDEM_PAIRS, WALL, PINCER, STEP_WALL }

@export var enemy_scene: PackedScene
@export var count: int = 6
@export var spawn_interval: float = 0.35
@export var spawn_delay: float = 0.5
@export var formation: int = Formation.TOP_LEFT_TO_RIGHT
# 320×400 res rework — halved.
@export var formation_padding: float = 32.0
@export var spawn_y: float = -12.0
# Tandem-pair X offset from CENTER (formation TOP_TANDEM_PAIRS). Two enemies
# spawn simultaneously at (CENTER - offset, CENTER + offset) sharing the same
# movement pattern (duplicated so each owns its state).
@export var tandem_offset_x: float = 30.0

# Per-wave overrides applied by the director after instantiating each enemy.
# Negative ints / null means "don't override; use the scene's default".
@export var movement_override: Resource = null
@export var shoot_pattern_override: Resource = null
# Behavior components to attach to each spawned enemy (m6 §3 component framework).
# Untyped Array — assigning a typed Array[Resource] from an untyped source is a runtime
# crash. Empty = none. Built by Roster.make_components(); applied in director._spawn_enemy.
@export var components_override: Array = []
@export var fire_interval_min: float = -1.0
@export var fire_interval_max: float = -1.0
@export var max_health: int = -1
@export var health_bonus: int = 0
@export var bounty_value: int = -1

@export var shield_charges: int = 0
@export var recycle_passes: int = -2   # -2 = don't override; -1 = unlimited; 0+ = N passes
# Firecore Drone ring count override (-1 = use scene/script default). Lets a
# wave dial the number of orbiting bullet rings (1-4) per drone so different
# comps cover different amounts of screen on death (Roman, 2026-05-31).
@export var ring_count_override: int = -1

# Sub-wave flag. Silent waves don't show the WAVE banner and don't wait for it
# to fade — they spawn after their own spawn_delay. Mark every wave AFTER an
# announced one with silent=true to roll multiple bursts under a single banner.
@export var silent: bool = false
# Optional custom banner text. When non-empty, the wave banner shows this
# string instead of "WAVE N / M". Used for hazards ("MINEFIELD DETECTED",
# "COLLISION WARNING") and the boss ("HIGH VALUE TARGET INCOMING").
@export var announce_text: String = ""
