extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const DroneScene = preload("res://scenes/player/player_drone.tscn")

# Drone Bits — Gradius-style Options. Equipped via HARDPOINT_WING, but
# the drones piggyback the PRIMARY fire trigger: every time the player's
# primary cannon fires, each equipped drone also spawns a bullet from
# its position. Mk scales drone count (1 → up to 5).
#
# Drones are children of the player so they follow movement naturally.
# Offsets fan out left + right of center, with later Mk drones placed
# further out.

@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var dmg_per_mark: int = 1
@export var base_drones: int = 1
@export var drones_per_mark: int = 1
@export var max_drones: int = 5
@export var halfspan: float = 18.0

var _spawned_drones: Array = []


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Drone Bits"
	description = "Orbital companion drones fire alongside primary. Mk adds more drones."


func apply(ship) -> void:
	# Spawn N drones as children of the ship, plus register them on the
	# ship so fire_primary can read them and add extra muzzles.
	var n: int = mini(base_drones + (int(mark) - 1) * drones_per_mark, max_drones)
	_spawned_drones.clear()
	for i in n:
		var offset_x: float = 0.0
		if n > 1:
			var t: float = float(i) / float(n - 1)
			offset_x = -halfspan + halfspan * 2.0 * t
		var drone = DroneScene.instantiate()
		drone.position = Vector2(offset_x, -2.0)
		ship.add_child.call_deferred(drone)
		_spawned_drones.append(drone)
	if "drone_bits" in ship:
		ship.drone_bits = _spawned_drones
	if "drone_bits_damage" in ship:
		ship.drone_bits_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	if "drone_bits_bullet_scene" in ship:
		ship.drone_bits_bullet_scene = bullet_scene


func unapply(ship) -> void:
	for d in _spawned_drones:
		if is_instance_valid(d):
			d.queue_free()
	_spawned_drones.clear()
	if "drone_bits" in ship:
		ship.drone_bits = []
	if "drone_bits_bullet_scene" in ship:
		ship.drone_bits_bullet_scene = null


# Editor readout — total per-shot damage from all drones combined.
func effective_damage(at_mark: int) -> int:
	var per_drone: int = base_damage + (at_mark - 1) * dmg_per_mark
	var n_drones: int = mini(base_drones + (at_mark - 1) * drones_per_mark, max_drones)
	return per_drone * n_drones
