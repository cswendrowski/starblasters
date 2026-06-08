extends "res://scripts/parts/secondary_weapon.gd"

# Combat Drones — SECONDARY weapon (HARDPOINT_WING). Tap the secondary fire
# action (shoot2) → DEPLOYS a burst of companion drones (2-6, by Mk) for a
# timed duration. The drones tether to the ship and autonomously fire at
# bosses-first, otherwise the nearest enemy.
#
# Roman 2026-05-30 rework: converted from a SUPER (DEVICE_BAY_1) to a
# SECONDARY. The deploy is a timed deployable secondary (SecondaryMode.DEPLOY,
# mirroring the Rocket Pod's BURST mode). The Part only sets knobs + spawns
# the wave on deploy(); the player owns the duration countdown, the active
# gate (no re-deploy while live), the deploy-ammo decrement, and the HUD
# timer. See player._tick_deploy.
#
# "Ammo" = number of deploys available, scaled by base_charges/charges_per_mark
# (kept from the old super-charge plumbing). Each press consumes one deploy.
#
# Mk scales drone COUNT + DURATION (alternating +1s then +1 drone):
#   Mk1: 2 drones / 8.0s   Mk2: 2 / 9.0   Mk3: 3 / 9.0    Mk4: 3 / 10.0
#   Mk5: 4 / 10.0          Mk6: 4 / 11.0  Mk7: 5 / 11.0   Mk8: 5 / 12.0
#   Mk9: 6 / 12.0
# Drones spread out around the player on spawn and avoid each other
# (boids separation lives in autonomous_drone.gd). When the duration
# expires the drones darken + fall away (shutdown anim, also in the drone).
#
# NOTE: internal class/file/.tres names are kept as "drone_swarm" — they
# are loadout serialization keys, not player-facing text.

const WSd = preload("res://scripts/weapons/WeaponStyle.gd")

const DroneScene = preload("res://scenes/player/player_drone.tscn")

# Distance drones spawn out from the ship center so they don't stack.
const SPAWN_RADIUS: float = 16.0

# Deploy-ammo @exports — formerly inherited from super_part.gd. Re-declared
# here so resources/weapons/drone_swarm.tres (which sets base_charges /
# charges_per_mark) still deserializes onto this script. These drive the
# number of DEPLOYS available, surfaced as the secondary ammo count.
@export var base_charges: int = 1
@export var charges_per_mark: int = 1


# Mk -> drone count. 2 + floor((mark-1)/2): 2,2,3,3,4,4,5,5,6 for Mk1-9.
func _drones_at_mark(at_mark: int) -> int:
	return 2 + (at_mark - 1) / 2


# Mk -> duration seconds. 8 + floor(mark/2): 8,9,9,10,10,11,11,12,12 for Mk1-9.
# Roman 2026-05-30: base timer raised 5s -> 8s.
func _duration_at_mark(at_mark: int) -> float:
	return 8.0 + float(at_mark / 2)


# Number of deploys available at a given Mk (the secondary "ammo" count).
func _charges_at_mark(at_mark: int) -> int:
	return base_charges + (at_mark - 1) * charges_per_mark


func _init() -> void:
	super._init()
	display_name = "Combat Drones"
	description = "Deploys a timed burst of companion drones that fire alongside your primary. Mk adds drones and duration. Secondary."


# Deploy pipeline mode — player._tick_deploy owns the lifecycle.
func _secondary_mode() -> int:
	return WSd.SecondaryMode.DEPLOY


func _snapshot_keys() -> Array:
	# DEPLOY mode reads none of the bullet-secondary knobs; we only drive
	# secondary_mode. Snapshot it so unequip restores the prior secondary.
	return ["secondary_mode"]


# No Mk-scaled ship knobs — count/duration are read off this Part at deploy
# time, not written onto the ship.
func _mk_knobs() -> Dictionary:
	return {}


func _apply_visuals(ship) -> void:
	if "secondary_mode" in ship:
		ship.secondary_mode = _secondary_mode()
	# Seed deploy ammo (= number of deploys). Survives scene changes via the
	# Run snapshot, same as the metered bullet secondaries.
	if ship.has_method("set_secondary_ammo"):
		var deploys: int = _charges_at_mark(int(mark))
		var seeded: int = deploys
		if ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if "secondary_ammo" in run and int(run.secondary_ammo) >= 0:
				seeded = int(run.secondary_ammo)
		ship.set_secondary_ammo(seeded, deploys)
	# Tell the player how long a deploy lasts so its countdown matches Mk.
	if "secondary_deploy_duration" in ship:
		ship.secondary_deploy_duration = _duration_at_mark(int(mark))
	# Reset any live deploy state so a re-equip never resumes a stale wave.
	if "_drones_active" in ship:
		ship._drones_active = false
	if "_deploy_timer" in ship:
		ship._deploy_timer = 0.0


func _on_unapply(ship) -> void:
	# Clear ammo metering + any live wave gate so the next secondary starts clean.
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)
	if "_drones_active" in ship:
		ship._drones_active = false
	if "_deploy_timer" in ship:
		ship._deploy_timer = 0.0


# Spawn one wave of drones around the ship and return the spawned nodes.
# Called by player._tick_deploy on a deploy press; the player owns the
# duration timer + cleanup from here on. Drones are children of the tree
# root (per convention) so they survive the spawner's queue_free.
func deploy(ship) -> Array:
	var spawned: Array = []
	if not ship.has_method("get_tree"):
		return spawned
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return spawned
	var n: int = _drones_at_mark(int(mark))
	for i in n:
		var drone = DroneScene.instantiate()
		# Spread drones evenly around the player on spawn so they don't
		# stack into a single pixel; boids separation keeps them apart after.
		var angle_seed: float = TAU * float(i) / float(max(1, n))
		# Emit from the player CENTER (Roman: drones should spawn at the ship,
		# not on a wing-halfspan ring); angle_seed still seeds the boids fan-out
		# so they spread apart immediately after.
		drone.position = ship.global_position
		tree.root.call_deferred("add_child", drone)
		drone.call_deferred("bind_player", ship, angle_seed)
		spawned.append(drone)
	# Drones just appear — no explosion/flash VFX (Roman 2026-05-29).
	return spawned


# Duration of a deploy at the current mark (queried by the player so the
# countdown timer starts at the right value).
func deploy_duration() -> float:
	return _duration_at_mark(int(mark))


func effective_damage(at_mark: int) -> int:
	# Surrogate "power" metric for the weapon editor: drones × duration.
	return int(round(float(_drones_at_mark(at_mark)) * _duration_at_mark(at_mark)))
