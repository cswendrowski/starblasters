class_name Phrase
extends Resource

# The atomic dispatch unit inside a Wave (combat bridge §0/§2). Replaces the
# flat WaveSpec.count batch model. A Phrase is one of three kinds; the conductor
# (M4) reads them in order and realizes placement/paths/deconfliction.
#
# This is INERT data scaffolding (M3): nothing consumes a Phrase yet. The exact
# field shape will harden as the conductor is built against it. See
# docs/combat_lane_wave_bridge_2026-06-03.md §2.

enum Kind { FORMATION, FILLER, BREATHER }

@export var kind: Kind = Kind.FILLER

# --- FORMATION: a composed group spawned as a coordinated burst (§2.1). ---
@export_group("Formation")
# Each member is a Dictionary: { chassis: StringName, tier: int,
# faction: StringName, count: int }. (Loose for now; may harden into a
# FormationMember Resource once the conductor consumes it.)
@export var members: Array = []
# Formation-pattern id (V, wall, pincer, checkerboard, every-other, echelon…),
# expressed by the conductor in RELATIVE lane offsets so it anchors + mirrors.
@export var shape: StringName = &""
@export var entry: StringName = &"top"        # "top" | "side"
@export var lane_anchor_hint: int = -1        # -1 = conductor chooses anchor

# --- FILLER: connective single-enemy trickle between formations (§2.2). ---
@export_group("Filler")
# Weighted pool, each entry: { chassis, tier, faction, weight }.
@export var pool: Array = []
@export var rate: float = 1.0                  # target trickle (enemies/sec), cap-gated
@export var until: StringName = &"headroom"    # "duration" | "budget" | "headroom"
@export var until_value: float = 0.0           # seconds or budget-share, per `until`

# --- BREATHER: a deliberate low/no-spawn gap (§2.3). ---
@export_group("Breather")
@export var duration: float = 1.0              # seconds
@export var alive_floor: int = -1              # >=0 = also wait until alive<=floor
