class_name CombatScore
extends Resource

# The "level score" — what wave-gen authors and the conductor performs
# (bridge §3: "wave-gen authors the score; the conductor performs it").
# Replaces the flat LevelData.waves array with an ordered Wave→Phrase structure.
#
# INERT scaffolding (M3): no producer emits a CombatScore and no consumer reads
# one yet. The transient score_adapter (lifting flat WaveSpec arrays) and the
# conductor that walks this come in M4. See
# docs/combat_lane_wave_bridge_2026-06-03.md §3.1 and
# docs/combat_construction_plan_2026-06-03.md §1.

@export var level_name: String = ""
@export var waves: Array[ScoreWave] = []
