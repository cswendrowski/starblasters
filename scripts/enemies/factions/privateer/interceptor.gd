extends "res://scripts/enemies/enemy_core.gd"

# Interceptor / Wing. Dives top→bottom quickly, dropping homing missiles on the way through. The
# missile-drop USED to live here as bespoke logic; it was generalized into an EmitterComponent
# (roster "emitters": a band-gated, drops-per-pass TIMER emit of drifting_missile.tscn) on 2026-06-17,
# so any enemy can carry it and the Enemy Bench can tune it.
#
# This script now only carries the no-recycle exit: interceptors leave the bottom and STAY GONE,
# rather than running enemy_core's parallax fly-back.


# Override the cycle hook from enemy_core so interceptors don't recycle.
func _start_cycle() -> void:
	# Mark the enemy as cycling so the rest of _process skips it, then defer-free instead of fly-back.
	_cycling = true
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	queue_free()
