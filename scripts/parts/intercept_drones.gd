extends "res://scripts/parts/module_part.gd"

# Intercept Drones — defensive Module (2026-06-13; migrated from the HARDPOINT_WING
# secondary, Mk scaling carried over). Ablative drones hold a forward ARC over the
# ship's nose and dart at incoming bullets (2026-07-16 behavior pass — see
# shield_drone.gd) — each takes base_hits + (Mk-1)*hits_per_mark hits before popping.
# Spawned at the START of every combat (the module apply loop runs at player _ready);
# once all are destroyed that's it for the level — they respawn next level.
# Default-safe: no drones unless equipped.
#
# Scene: scenes/player/shield_drone.tscn (placeholder art — swap the sprite when the
# dedicated module-drone art lands).

const ShieldDroneScene = preload("res://scenes/player/shield_drone.tscn")

@export var base_drones: int = 3
@export var base_hits: int = 2
@export var hits_per_mark: int = 1
@export var arc_radius: float = 24.0
@export var arc_spread_deg: float = 110.0

var _spawned_drones: Array = []


func _init() -> void:
	super._init()
	module_id = "intercept_drones"
	display_name = "Intercept Drones"
	description = "Drones screen the space ahead of your ship, darting to intercept incoming bullets — each takes a few hits before popping. Mk adds +1 hit per drone. They respawn each level; once gone, they're gone for that level."


func apply(ship) -> void:
	# Presentation copies of the real player (loading-screen fly-through, player FX lab)
	# set controls_enabled = false BEFORE add_child, so it's false here at module-apply
	# time — no drone screen on those (Roman 2026-07-16). Real combat applies modules
	# while controls are still on (main disables them only later, for the intro).
	if "controls_enabled" in ship and not ship.controls_enabled:
		return
	_spawn_drones(ship)


func unapply(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()


func _spawn_drones(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	var n: int = base_drones
	var hp: int = base_hits + (int(mark) - 1) * hits_per_mark
	for i in n:
		var drone = ShieldDroneScene.instantiate()
		# Parented under the tree root so the formation survives ship rotation (position is
		# driven manually in the drone's _process). IMMEDIATE add + bind — NEVER deferred:
		# main._install_chosen_player() free()s the baked Player right after its _ready
		# (which ran this apply), and the module re-applies on the swapped-in variant. With
		# deferred adds, that second apply queue_free()d drones whose add_child was still
		# queued → add_child on freed objects → heap-corruption CTD (Hive, 2026-07-16).
		# bind_player is plain var writes, so it doesn't need the drone's _ready first.
		ship.get_tree().root.add_child(drone)
		drone.bind_player(ship, i, n, hp)
		drone.arc_radius = arc_radius
		drone.arc_spread_deg = arc_spread_deg
		_spawned_drones.append(drone)


# Editor readout — total drone hit pool across all drones at this Mk.
func effective_damage(at_mark: int) -> int:
	return (base_hits + (at_mark - 1) * hits_per_mark) * base_drones


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var hits: int = base_hits + (m - 1) * hits_per_mark
	return "%d drones, %d hits each" % [base_drones, hits]
