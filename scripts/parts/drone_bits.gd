extends "res://scripts/parts/part.gd"

# Filename retained for .tres compatibility — Part renamed Drone Bits → Intercept Drones (2026-05-24).

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const ShieldDroneScene = preload("res://scenes/player/shield_drone.tscn")

# Intercept Drones — secondary slot. Cobalt 2026-05-21 redesign: previously
# these piggybacked the primary fire (Gradius Options). Now they orbit
# the player at ~18 px and act as an ablative bullet/collision shield.
# Each drone takes 2 hits at Mk.1, +1 per Mk. Default count is 3 spinning
# drones spawned on equip and persisting until destroyed.
#
# When equipped, spawns the drones immediately. When unequipped (or part
# swapped), the drones are freed. They don't fire.

@export var base_drones: int = 3
@export var max_drones: int = 3
@export var base_hits: int = 2
@export var hits_per_mark: int = 1
@export var orbit_radius: float = 18.0
@export var orbit_speed: float = 2.4

var _spawned_drones: Array = []
var _prev_drone_bits: Array = []
var _had_prev_drone_bits: bool = false


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Intercept Drones"
	description = "3 spinning drones orbit your ship and intercept incoming bullets. Mk adds +1 hit per drone."


func apply(ship) -> void:
	# No drones on presentation copies (loading screen / FX lab) — they set
	# controls_enabled = false before add_child. See intercept_drones.apply.
	if "controls_enabled" in ship and not ship.controls_enabled:
		return
	_spawn_drones(ship)
	# Clear any drone_bits primary-piggyback hook left over from the old
	# design — fire_primary checks this array, and we don't want shield
	# drones contributing extra bullets. Snapshot first so unapply can restore.
	if "drone_bits" in ship:
		_prev_drone_bits = ship.drone_bits.duplicate()
		_had_prev_drone_bits = true
		ship.drone_bits = []


func unapply(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	if "drone_bits" in ship:
		if _had_prev_drone_bits:
			ship.drone_bits = _prev_drone_bits
		else:
			ship.drone_bits = []
	_prev_drone_bits = []
	_had_prev_drone_bits = false


func _spawn_drones(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	var n: int = mini(base_drones, max_drones)
	var hp: int = base_hits + (int(mark) - 1) * hits_per_mark
	# Drones are parented under the SceneTree root so the formation survives ship
	# rotation (position driven manually in _process). bind_player gives each drone
	# its arc slot index (2026-07-16: forward arc, shared with the module version).
	# IMMEDIATE add + bind — never deferred: the combat-load player swap re-applies
	# parts and a deferred add racing that swap's queue_free was a heap-corruption
	# CTD (see intercept_drones._spawn_drones, same fix).
	for i in n:
		var drone = ShieldDroneScene.instantiate()
		ship.get_tree().root.add_child(drone)
		drone.bind_player(ship, i, n, hp)
		_spawned_drones.append(drone)


# Editor readout — total drone hit pool across all drones at this Mk.
func effective_damage(at_mark: int) -> int:
	var per_drone: int = base_hits + (at_mark - 1) * hits_per_mark
	return per_drone * mini(base_drones, max_drones)
