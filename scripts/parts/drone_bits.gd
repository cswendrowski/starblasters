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


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Intercept Drones"
	description = "3 spinning drones orbit your ship and intercept incoming bullets. Mk adds +1 hit per drone."


func apply(ship) -> void:
	_spawn_drones(ship)
	# Clear any drone_bits primary-piggyback hook left over from the old
	# design — fire_primary checks this array, and we don't want shield
	# drones contributing extra bullets.
	if "drone_bits" in ship:
		ship.drone_bits = []


func unapply(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	if "drone_bits" in ship:
		ship.drone_bits = []


func _spawn_drones(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	var n: int = mini(base_drones, max_drones)
	var hp: int = base_hits + (int(mark) - 1) * hits_per_mark
	# Drones are parented under the SceneTree root so they keep their
	# orbit even if the ship rotates (we drive position manually in
	# _process). bind_player gives each drone its starting angle so the
	# three are evenly spaced.
	for i in n:
		var drone = ShieldDroneScene.instantiate()
		var start_angle: float = TAU * (float(i) / float(n))
		ship.get_tree().root.call_deferred("add_child", drone)
		# Defer the bind so the drone's _ready has fired first.
		drone.call_deferred("bind_player", ship, start_angle, hp)
		drone.call_deferred("set", "orbit_radius", orbit_radius)
		drone.call_deferred("set", "orbit_speed", orbit_speed)
		_spawned_drones.append(drone)


# Editor readout — total drone hit pool across all drones at this Mk.
func effective_damage(at_mark: int) -> int:
	var per_drone: int = base_hits + (at_mark - 1) * hits_per_mark
	return per_drone * mini(base_drones, max_drones)
