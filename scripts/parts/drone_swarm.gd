extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
# player_drone.tscn now bundles the Area2D + Sprite2D + CollisionShape +
# the autonomous behaviour script. drone_swarm just instantiates and
# binds; no script swap.
const DroneScene = preload("res://scenes/player/player_drone.tscn")

# Drone Swarm — super weapon. Tap X (shoot_nose) → spawns a burst of
# 4-6 player drones for ~5 seconds. The drones behave like Drone Bits
# while active: they parent to the ship, follow movement, and
# piggyback the primary's fire (one extra bullet per shot per drone).
#
# Stacks with an equipped Drone Bits secondary — the swarm drones
# append to the player's drone_bits array, get cleaned up on timeout.
#
# Cody 2026-05-20: simplified design — drones don't independently
# target. Hold primary fire to make use of the swarm output.

@export var base_duration: float = 5.0
@export var duration_per_mark: float = 0.5
@export var base_drones: int = 4
@export var drones_per_mark: int = 0  # constant count per Mk; duration scales instead
@export var max_drones: int = 6
@export var halfspan: float = 24.0
@export var base_charges: int = 1
@export var charges_per_mark: int = 1


func _init() -> void:
	slot_type = Slots.SlotType.DEVICE_BAY_1
	display_name = "Drone Swarm"
	description = "Summons a 5s burst of companion drones that fire alongside primary."


func apply(ship) -> void:
	if not ("super_part" in ship):
		return
	ship.super_part = self
	ship.max_super_charges = base_charges + (int(mark) - 1) * charges_per_mark
	ship.super_charges = ship.max_super_charges
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)


func unapply(ship) -> void:
	if not ("super_part" in ship):
		return
	if ship.super_part == self:
		ship.super_part = null
		ship.super_charges = 0
		if ship.has_signal("super_charges_changed"):
			ship.super_charges_changed.emit(0, 0)


func activate(ship) -> void:
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	var n: int = mini(base_drones + (int(mark) - 1) * drones_per_mark, max_drones)
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	# Cobalt 2026-05-21: drones are now autonomous — tethered to the
	# player and free to pick their own targets (bosses first, otherwise
	# nearest enemy). They fire the basic blaster bullet.
	var spawned: Array = []
	for i in n:
		var drone = DroneScene.instantiate()
		# player_drone.tscn is already an Area2D with the autonomous
		# script's required setup. Cobalt 2026-05-21 also asked for drones
		# to spawn from the player's center, so start them at the player's
		# global position; the autonomous _process tether-orbits them out.
		drone.position = ship.global_position
		tree.root.call_deferred("add_child", drone)
		var angle_seed: float = TAU * float(i) / float(max(1, n))
		drone.call_deferred("bind_player", ship, angle_seed)
		spawned.append(drone)
	# Activation flare — spawn-puff per drone so each one reads as
	# physically emerging from the ship, plus a central flash. Distinct
	# from Smart Bomb (chain of blasts), Phase Shift (wide ring), and
	# Hyper (single big punch).
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.play(ship.global_position, 1.0, true)
		ExplosionFx.burst(ship.global_position, n, 12.0, 0.03)
	var main: Node = tree.get_current_scene()
	if main and main.has_node("Camera2D"):
		var cam = main.get_node("Camera2D")
		if cam.has_method("add_trauma"):
			cam.add_trauma(0.35)
	# Schedule cleanup after duration.
	var cleanup_timer := tree.create_timer(dur)
	cleanup_timer.timeout.connect(func():
		for d in spawned:
			if is_instance_valid(d):
				d.queue_free()
	)


func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 10.0))
