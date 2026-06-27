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
# Authored explicit lane (wave pattern editor, 2026-06-16): 0..Lanes.COUNT-1 pins this spec to
# that exact lane; -1 = unset (algorithmic placement). Consumed by director._dispatch_authored,
# which passes it as lane_override to _spawn_enemy (spawns at Lanes.lane_center(lane)).
@export var lane: int = -1
# Geometric formation shape (conductor readability pass, 2026-06-23). When non-empty, the wave is
# performed as a held, pre-stacked BURST in this shape (vee/chevron/diamond/echelon/columns) instead
# of the random-spread trickle — the count-N spec is exploded across formation_shapes.placements()
# by director._dispatch_geometric. "" = unset (the Formation enum drives placement, production
# default). ScoreAdapter._shape_id prefers this over the legacy enum when set.
@export var shape_override: StringName = &""
# Hazard lateral-drift mode (Roman 2026-06-23): "" = leave the hazard's own default; otherwise
# "straight"/"drift_lane"/"drift_adjacent"/"drift_all" picks the LateralDrift envelope. Applied by
# director._spawn_enemy to any spawn exposing a `drift_mode` property (asteroid/mine/firecore);
# ignored by everything else. Authored hazard patterns map their placement movement onto this.
@export var drift_mode: String = ""
# Sub-lane X offset (px) added to the lane centre — lets the Formation Builder pack a sub-grid of
# enemies into one lane square. 0 = lane centre (default, production unchanged). Lane-pinned only.
@export var spawn_x_offset: float = 0.0
# Lateral-direction override (Formation Builder, 2026-06-17). Forces which way a
# side-aware movement (side_traverse/side_cut/side_pingpong's `direction`, or
# lane_path's `mirrored` flip) runs, instead of leaving it as authored:
#   0 = leave as authored (default, production unchanged)
#   1 = right (+X)   -1 = left (-X)   2 = random per-spawn (seeded ±1)
# director._spawn_enemy applies it just before add_child; only patterns that
# expose `direction` or `mirrored` are touched.
@export var direction_override: int = 0
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
# Firing mounts (extra guns/turrets/launchers/beams beyond shoot_pattern), as MountSpec resources.
# Untyped Array (same crash reason as above). Empty = none. Built by Roster.make_mounts(); applied
# in director._spawn_enemy before add_child so enemy_base._attach_mounts realizes them.
@export var mounts_override: Array = []
@export var fire_interval_min: float = -1.0
@export var fire_interval_max: float = -1.0
@export var max_health: int = -1
@export var health_bonus: int = 0
@export var bounty_value: int = -1

@export var shield_charges: int = 0
@export var recycle_passes: int = -2   # -2 = don't override; -1 = unlimited; 0+ = N passes
# Locomotion (locomotion refactor 2026-06-19): resolved chassis stats from Roster.compose_stats
# (size base rung + engine + overrides). 0 = unset (keep the enemy scene / pattern fallback).
# depth_override < 0 = no formation/roster depth (enemy keeps its scene default). Applied per-spawn
# in director._spawn_enemy; movement patterns read them via movement_pattern.gd's accessors.
@export var move_speed: float = 0.0
@export var weight: float = 0.0
@export var turn_rate: float = 0.0
@export var accel: float = 0.0
@export var depth_override: float = -1.0
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
