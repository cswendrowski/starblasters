extends "res://scripts/boss.gd"

# Reaver — aggressive mid-HP boss. Trades the Commander's minion + black-hole
# kit for raw firepower: faster movement, tighter bullet cadence, no minions
# or black holes.

func _ready() -> void:
	# Override stats before the base _ready runs (which would otherwise pull
	# default values from the .gd's @export defaults). We can mutate the
	# @export fields and they take effect for the base init.
	max_health = 200  # ×2 balance pass 2026-05-22
	bounty_value = 250
	display_scale = 1.0
	fire_interval_min = 0.35
	fire_interval_max = 0.65
	# No minion stream; null the scene so the base script's fallback diver
	# spawn never fires.
	minions_per_spawn = 0
	minion_max_alive = 0
	# Push the black-hole cadence so far out it never fires inside a level —
	# Reaver doesn't do that move.
	black_hole_interval_min = 9999.0
	black_hole_interval_max = 9999.0
	super._ready()
