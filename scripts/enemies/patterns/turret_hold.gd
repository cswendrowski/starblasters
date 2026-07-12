extends "res://scripts/enemies/movement_pattern.gd"

# Immobile turret emplacement (Roman 2026-07-12). The base flies in from the spawn point, DECELERATES
# is not needed — it just descends at chassis speed to a hold depth then STOPS DEAD: no jiggle, no
# drift. The base is a fixed platform; the aiming/tracking is done by the turret LAYER (a TURRET
# hardpoint that rotates toward the player). Used by the core turret (enemy_core_building_turret).
#
# Why a movement at all (vs. a truly stationary null-movement enemy): enemies spawn at the top edge
# (bench spawns at y=-12), so a null-movement turret would sit off-screen. Descending to a hold depth
# brings it on-screen for both the live wave and the Enemy Bench, then locks it in place.
#
# Path-phase capable: the descent to the hold is monotonic in band-Y.

const ZonesC = preload("res://scripts/systems/zones.gd")

@export var hold_depth_px: float = 96.0   # Y to settle at when the enemy carries no depth override

var _arrived: bool = false


func on_start(_enemy) -> void:
	_arrived = false


func compute_step(enemy, delta: float) -> Vector2:
	if _arrived:
		return Vector2.ZERO   # fixed emplacement — dead still once settled
	# Resolve the hold Y: an explicit per-enemy/formation depth wins, else the pattern default.
	var depth: float = hold_depth_px
	if "depth_bp" in enemy and enemy.depth_bp >= 0.0:
		depth = ZonesC.y_for_progress(enemy.depth_bp)
	var arr := [false]
	var sy: float = descend_to(enemy, depth, _move_speed(enemy), delta, arr)
	if arr[0]:
		_arrived = true
	return Vector2(0.0, sy)


func path_phase_capable() -> bool:
	return true   # monotonic descent to the hold
