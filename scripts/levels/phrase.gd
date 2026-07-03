class_name Phrase
extends Resource

# The atomic dispatch unit inside a Wave (combat bridge §0/§2). Replaces the
# flat WaveSpec.count batch model as the COMPOSITION/SCHEDULING layer — but it
# composes ON TOP of WaveSpec, which stays the materialization descriptor that
# director._spawn_enemy consumes (what enemy + count + overrides). The conductor
# decides WHEN (dispatch) and WHERE (lane), then materializes via a WaveSpec.
#
# INERT scaffolding (M3) until the conductor consumes it (M4). See
# docs/combat_lane_wave_bridge_2026-06-03.md §2.

enum Kind { FORMATION, FILLER, BREATHER }

@export var kind: Kind = Kind.FILLER

# --- FORMATION: a composed group spawned as a coordinated burst (§2.1). ---
@export_group("Formation")
# Array of WaveSpec resources (one per enemy type in the group; .count each).
# WaveSpec is the existing materialization descriptor (scripts/levels/wave_def.gd).
@export var specs: Array = []
# Lane-relative formation layout id (V, wall, pincer, every-other, echelon…),
# resolved by the conductor and anchored + mirrored. During the adapter era it
# also carries lifted legacy Formation ids (left_to_right, center_out, …).
@export var shape: StringName = &"top_spread"
@export var entry: StringName = &"top"        # "top" | "side"

# --- FILLER: connective single-enemy trickle between formations (§2.2). ---
@export_group("Filler")
@export var pool: Array = []                   # Array of WaveSpec resources to trickle from
@export var rate: float = 1.0                  # target trickle (enemies/sec), cap-gated
@export var until: StringName = &"headroom"    # "duration" | "budget" | "headroom"
@export var until_value: float = 0.0           # seconds or budget-share, per `until`

# --- BREATHER: a deliberate low/no-spawn gap (§2.3). ---
@export_group("Breather")
@export var duration: float = 1.0              # seconds
@export var alive_floor: int = -1              # >=0 = also wait until alive<=floor
