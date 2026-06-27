extends "res://scripts/parts/module_part.gd"

# Intercept Drones — defensive Module (2026-06-13; migrated from the HARDPOINT_WING
# secondary, Mk scaling carried over). Spinning ablative drones orbit the ship and soak
# incoming bullets/collisions — each takes base_hits + (Mk-1)*hits_per_mark hits before
# popping. Spawned at the START of every combat (the module apply loop runs at player
# _ready); once all are destroyed that's it for the level — they respawn next level.
# Default-safe: no drones unless equipped.
#
# Scene: scenes/player/shield_drone.tscn (placeholder art — swap the sprite when the
# dedicated module-drone art lands).

const ShieldDroneScene = preload("res://scenes/player/shield_drone.tscn")

@export var base_drones: int = 3
@export var base_hits: int = 2
@export var hits_per_mark: int = 1
@export var orbit_radius: float = 18.0
@export var orbit_speed: float = 2.4

var _spawned_drones: Array = []


func _init() -> void:
	super._init()
	module_id = "intercept_drones"
	display_name = "Intercept Drones"
	description = "Spinning drones orbit your ship and soak incoming bullets — each takes a few hits before popping. Mk adds +1 hit per drone. They respawn each level; once gone, they're gone for that level."


func apply(ship) -> void:
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
		var start_angle: float = TAU * (float(i) / float(n))
		# Parented under the tree root so the orbit survives ship rotation (position is
		# driven manually in the drone's _process). Deferred so the drone's _ready fires first.
		ship.get_tree().root.call_deferred("add_child", drone)
		drone.call_deferred("bind_player", ship, start_angle, hp)
		drone.call_deferred("set", "orbit_radius", orbit_radius)
		drone.call_deferred("set", "orbit_speed", orbit_speed)
		_spawned_drones.append(drone)


# Editor readout — total drone hit pool across all drones at this Mk.
func effective_damage(at_mark: int) -> int:
	return (base_hits + (at_mark - 1) * hits_per_mark) * base_drones


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var hits: int = base_hits + (m - 1) * hits_per_mark
	return "%d drones, %d hits each" % [base_drones, hits]
