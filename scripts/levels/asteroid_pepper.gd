extends Node2D

# Asteroid pepper (Roman 2026-07-18, stronghold-assault go-live): the light enemy-asteroid overlay for
# STANDARD COMBAT on an asteroid POI. The retired asteroid_field hazard node's conducted rock waves are
# gone — a combat level on an asteroid POI now just peppers destructible rocks (enemy_asteroid.tscn)
# through the fight, alongside the director's normal faction waves. Rocks fly UNDER the combatants
# (asteroid.gd pins z -1) and receive the flyover drop shadows.
#
# Self-regulating, zero director coupling: rocks spawn only while a live NON-HAZARD combatant is on the
# field (i.e. while the fight is actually happening), so the pepper pauses between waves and stops for
# good once the last wave drains — spawned rocks then free off the bottom and the director's
# level_cleared fires (rocks are is_hazard and DO gate the clear, so the stop matters).
#
# Tunable via Run meta "asteroid_pepper_knobs" {interval_min, interval_max, first_delay}.

const RockScene := preload("res://scenes/enemies/enemy_asteroid.tscn")

var interval_min: float = 4.0
var interval_max: float = 8.0
var first_delay: float = 2.5

var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func start(knobs: Dictionary = {}) -> void:
	interval_min = float(knobs.get("interval_min", interval_min))
	interval_max = float(knobs.get("interval_max", interval_max))
	first_delay = float(knobs.get("first_delay", first_delay))
	_timer = first_delay
	_rng.randomize()
	set_process(true)


func _process(delta: float) -> void:
	if not _combat_live():
		return   # between waves / level drained — hold (timer keeps its remainder)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(interval_min, interval_max)
	_spawn_rock()


# A live non-hazard, non-dying "enemies" node = the fight is on. Rocks themselves are is_hazard so a
# field of only rocks reads as "combat over" and the pepper stays quiet while they drain.
func _combat_live() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if "is_hazard" in n and n.is_hazard:
			continue
		if "_dying" in n and n._dying:
			continue
		return true
	return false


func _spawn_rock() -> void:
	var x: float = _rng.randf_range(Playfield.X_MIN + 12.0, Playfield.X_MAX - 12.0)
	var r := RockScene.instantiate()
	r.position = Vector2(x, -_rng.randf_range(40.0, 90.0))
	add_child(r)
	if r.has_method("start"):
		r.start(r.position)
