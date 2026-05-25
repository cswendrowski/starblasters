extends "res://scripts/parts/super_part.gd"

# Drone Swarm — super weapon. Tap X (shoot_nose) → spawns a burst of
# 4-6 player drones for ~5 seconds. The drones tether to the ship and
# autonomously fire at bosses-first, otherwise nearest enemy.
#
# Stacks with an equipped Drone Bits secondary — swarm drones append
# to the player's drone_bits array and get cleaned up on timeout.

const DroneScene = preload("res://scenes/player/player_drone.tscn")

@export var base_duration: float = 5.0
@export var duration_per_mark: float = 0.5
@export var base_drones: int = 4
@export var drones_per_mark: int = 0
@export var max_drones: int = 6
@export var halfspan: float = 24.0


func _init() -> void:
	super._init()
	display_name = "Drone Swarm"
	description = "Summons a 5s burst of companion drones that fire alongside primary."
	base_charges = 1
	charges_per_mark = 1


func activate(ship) -> void:
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	var n: int = mini(base_drones + (int(mark) - 1) * drones_per_mark, max_drones)
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	var spawned: Array = []
	for i in n:
		var drone = DroneScene.instantiate()
		# Spawn from the player's center; drone autonomous _process
		# tether-orbits out from there.
		drone.position = ship.global_position
		tree.root.call_deferred("add_child", drone)
		var angle_seed: float = TAU * float(i) / float(max(1, n))
		drone.call_deferred("bind_player", ship, angle_seed)
		spawned.append(drone)
	# Spawn-puff per drone + central flash. Distinct from Smart Bomb (chain
	# of blasts), Phase Shift (wide ring), Hyper (single big punch).
	_flash_at(ship, 1.0)
	_burst_at(ship, n, 12.0, 0.03)
	_camera_trauma(ship, 0.35)
	# Cleanup after duration.
	var cleanup_timer := tree.create_timer(dur)
	cleanup_timer.timeout.connect(func():
		for d in spawned:
			if is_instance_valid(d):
				d.queue_free()
	)


func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 10.0))
