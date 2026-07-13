extends "res://scripts/parts/secondary_weapon.gd"

# Combat Drones — SECONDARY weapon (HARDPOINT_WING). Roman 2026-07-08 REBUILD (scrapped the old
# timed orbit/intercept swarm). Tap the secondary fire action (shoot2) → spends 1 AMMO and spawns a
# wave of companion drones that flank the ship and blast the nearest threat. Each drone owns its own
# 30s lifetime (movement/firing/blue-disintegrate all live in autonomous_drone.gd), so waves overlap —
# the player just spawns the wave + decrements ammo (no wave gate / deploy timer). See player._tick_deploy.
#
# Mk scaling (see the three helpers below):
#   drone COUNT per fire = 1 + floor((mark-1)/2)  → +1 on each ODD mark → 1,1,2,2,3,3,4,4,5 (5 at Mk9)
#   AMMO (fires available)= 1 + floor(mark/3)      → +1 every 3 marks   → 1,1,1,2,2,2,3,3,4 (4 at Mk9)
#   BLASTER mark          = 1 + floor(mark/2)       → +1 on each EVEN mark→ 1,2,2,3,3,4,4,5,5 (drone dmg 2/mark)
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


# Mk -> drone count per fire (Roman 2026-07-08 rebuild). 1 + floor((mark-1)/2), i.e. +1 on each ODD mark:
# 1,1,2,2,3,3,4,4,5 for Mk1-9 (5 drones at Mk9).
func _drones_at_mark(at_mark: int) -> int:
	return 1 + (at_mark - 1) / 2


# Fixed 30s drone lifetime (mark-independent now; the drone owns its own countdown).
func _duration_at_mark(_at_mark: int) -> float:
	return 30.0


# Ammo = number of times the weapon can fire (Roman 2026-07-08). 1 + floor(mark/3), i.e. +1 every 3 marks:
# 1,1,1,2,2,2,3,3,4 for Mk1-9 (4 ammo at Mk9). Overrides the linear base_charges plumbing.
func _charges_at_mark(at_mark: int) -> int:
	return 1 + at_mark / 3


# Effective BLASTER mark the drones fire at. Base Mk1 blaster; each EVEN mark bumps it +1:
# 1 + floor(mark/2) → 1,2,2,3,3,4,4,5,5 for Mk1-9. Scales the drone bullet's damage (blaster is 2/mark).
func _blaster_mark_at(at_mark: int) -> int:
	return 1 + at_mark / 2


func _init() -> void:
	super._init()
	display_name = "Combat Drones"
	description = "Fires a wave of companion drones that flank your ship and blast the nearest threat for 30s. Mk adds drones, blaster power, and ammo. Secondary."


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
		# Sector Conditions — More Ammo scales the deploy-count CAP. Run-side
		# _seed_secondary_ammo can't seed drones (no base_ammo field), so this
		# ship apply is the SINGLE cap seam for the deploy count. The live
		# run.secondary_ammo (once positive) is the consumed remainder — used
		# as-is, never rescaled.
		var cap: int = deploys
		if ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if deploys > 0:
				cap = run.cond_ammo_cap(deploys)
			if "secondary_ammo" in run and int(run.secondary_ammo) >= 0:
				seeded = int(run.secondary_ammo)
			else:
				seeded = cap
		ship.set_secondary_ammo(seeded, cap)
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
	var blaster_mk: int = _blaster_mark_at(int(mark))
	# Drones spawn UNDER the player one at a time, 0.15s apart (drone owns the stagger via spawn_delay),
	# then slide to their flank slot (slot i alternates R/L, stacking outward). blaster_mk scales their shot.
	for i in n:
		var drone = DroneScene.instantiate()
		drone.position = ship.global_position + Vector2(0, 8.0)
		# Honor the ship's bullet_parent (the Hangar's SubViewport world) so drones render in the same
		# space as the player; else tree.root per convention (live game leaves bullet_parent null).
		var drone_parent: Node = tree.root
		if "bullet_parent" in ship and ship.bullet_parent != null:
			drone_parent = ship.bullet_parent
		drone_parent.call_deferred("add_child", drone)
		drone.call_deferred("bind", ship, i, 0.15 * float(i), blaster_mk)
		spawned.append(drone)
	return spawned


# Duration of a deploy at the current mark (queried by the player so the
# countdown timer starts at the right value).
func deploy_duration() -> float:
	return _duration_at_mark(int(mark))


func effective_damage(at_mark: int) -> int:
	# Surrogate "power" metric for the weapon editor: drones × duration.
	return int(round(float(_drones_at_mark(at_mark)) * _duration_at_mark(at_mark)))
