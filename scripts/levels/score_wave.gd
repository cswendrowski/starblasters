class_name ScoreWave
extends Resource

# A compositional section of a level (5–8 per level), with an identity (banner,
# dominant faction, enemy mix) and an ordered list of Phrases. Waves blend into
# one stream — banners are non-blocking markers, not clear-gates (bridge §0/§1).
#
# INERT scaffolding (M3): nothing consumes ScoreWave yet. See
# docs/combat_lane_wave_bridge_2026-06-03.md §3.1.

@export var banner: String = ""               # non-blocking wave marker text
@export var dominant_faction: StringName = &""
@export var phrases: Array[Phrase] = []
# Slot cap for this section = the density ceiling the director enforces while it plays (the 3-stretch
# ramp 16/26/36; level_structure_redesign_2026-07-01). -1 = leave max_concurrent unchanged.
@export var slot_cap: int = -1
