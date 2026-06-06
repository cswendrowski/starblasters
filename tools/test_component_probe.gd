extends EnemyComponent

# Probe component for test_components_framework.gd — records which hooks fire.
# Standalone .gd (not an inner class) so Resource.duplicate() preserves the script
# cleanly when enemy_base dupes it per-instance.

var started: bool = false
var processed: int = 0
var last_hit: int = -99
var died: bool = false
var left: bool = false


func on_start(_enemy) -> void:
	started = true


func on_process(_enemy, _delta: float) -> void:
	processed += 1


func on_hit(_enemy, damage: int) -> int:
	last_hit = damage
	return damage


func on_death(_enemy) -> void:
	died = true


func on_leave(_enemy) -> void:
	left = true
