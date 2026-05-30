extends "res://scripts/parts/super_part.gd"

# Combat Drones — super weapon. Tap X (shoot_nose) → spawns a burst of
# companion drones (2-6, by Mk) for a few seconds. The drones tether to
# the ship and autonomously fire at bosses-first, otherwise nearest enemy.
#
# Mk scales drone COUNT + DURATION (alternating +1s then +1 drone):
#   Mk1: 2 drones / 5.0s   Mk2: 2 / 6.0   Mk3: 3 / 6.0   Mk4: 3 / 7.0
#   Mk5: 4 / 7.0           Mk6: 4 / 8.0   Mk7: 5 / 8.0    Mk8: 5 / 9.0
#   Mk9: 6 / 9.0
# Drones spread out around the player on spawn and avoid each other
# (boids separation lives in autonomous_drone.gd).
#
# NOTE: internal class/file/.tres names are kept as "drone_swarm" — they
# are loadout serialization keys, not player-facing text.

const DroneScene = preload("res://scenes/player/player_drone.tscn")

# Distance drones spawn out from the ship center so they don't stack.
const SPAWN_RADIUS: float = 16.0

# Guard flag — true while a swarm is alive. Prevents re-activation before
# the current batch of drones despawns (Bug fix 2026-05-26).
var _drones_active: bool = false


# Mk -> drone count. 2 + floor((mark-1)/2): 2,2,3,3,4,4,5,5,6 for Mk1-9.
func _drones_at_mark(at_mark: int) -> int:
	return 2 + (at_mark - 1) / 2


# Mk -> duration seconds. 5 + floor(mark/2): 5,6,6,7,7,8,8,9,9 for Mk1-9.
func _duration_at_mark(at_mark: int) -> float:
	return 5.0 + float(at_mark / 2)


func _init() -> void:
	super._init()
	display_name = "Combat Drones"
	description = "Summons a timed burst of companion drones that fire alongside your primary. Mk adds drones and duration."
	base_charges = 1
	charges_per_mark = 1


func activate(ship) -> void:
	if _drones_active:
		return
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	var n: int = _drones_at_mark(int(mark))
	var dur: float = _duration_at_mark(int(mark))
	var spawned: Array = []
	_drones_active = true
	for i in n:
		var drone = DroneScene.instantiate()
		# Spread drones evenly around the player on spawn so they don't
		# stack into a single pixel; the boids separation in the drone's
		# _process keeps them apart afterwards.
		var angle_seed: float = TAU * float(i) / float(max(1, n))
		drone.position = ship.global_position + Vector2(cos(angle_seed), sin(angle_seed)) * SPAWN_RADIUS
		tree.root.call_deferred("add_child", drone)
		drone.call_deferred("bind_player", ship, angle_seed)
		spawned.append(drone)
	# Drones just appear — no explosion/flash VFX (Roman 2026-05-29: the
	# swarm should not spawn out of an explosion). A light camera nudge
	# stays as activation feedback; it is not an explosion.
	_camera_trauma(ship, 0.2)
	# Cleanup after duration.
	var cleanup_timer := tree.create_timer(dur)
	cleanup_timer.timeout.connect(func():
		for d in spawned:
			if is_instance_valid(d):
				d.queue_free()
		_drones_active = false
	)


func effective_damage(at_mark: int) -> int:
	# Surrogate "power" metric for the weapon editor: drones × duration.
	return int(round(float(_drones_at_mark(at_mark)) * _duration_at_mark(at_mark)))
