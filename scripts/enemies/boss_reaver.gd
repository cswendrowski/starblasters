extends "res://scripts/enemies/boss_base.gd"

# Reaver — aggressive mid-HP boss. Sweeper that pressures the player with
# the wave-director-injected SpreadShot on a tight cadence. No minions,
# no black hole — those are Commander's kit.

func _ready() -> void:
	max_health = 200
	bounty_value = 250
	display_scale = 1.0
	fire_interval_min = 0.35
	fire_interval_max = 0.65
	super._ready()
