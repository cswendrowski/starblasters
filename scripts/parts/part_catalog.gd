extends Node

# Catalog of every available part with a rolling-pool API for outposts.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const BasicEngine = preload("res://scripts/parts/basic_engine.gd")
const BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const HeavyBlaster = preload("res://scripts/parts/heavy_blaster.gd")
const VectoringEngine = preload("res://scripts/parts/vectoring_engine.gd")
const MachinegunCannon = preload("res://scripts/parts/machinegun_cannon.gd")
const RotaryLaserCannon = preload("res://scripts/parts/rotary_laser_cannon.gd")
const WaveGunCannon = preload("res://scripts/parts/wave_gun_cannon.gd")
const LaserBeamCannon = preload("res://scripts/parts/laser_beam_cannon.gd")
const RocketPodCannon = preload("res://scripts/parts/rocket_pod_cannon.gd")
const SeekingMissileCannon = preload("res://scripts/parts/seeking_missile_cannon.gd")
const SpreadCannon = preload("res://scripts/parts/spread_cannon.gd")
const SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
const HyperMode = preload("res://scripts/parts/hyper_mode.gd")
const PhaseShift = preload("res://scripts/parts/phase_shift.gd")
const ParticleBeam = preload("res://scripts/parts/particle_beam.gd")
const SidePods = preload("res://scripts/parts/side_pods.gd")
const DroneBits = preload("res://scripts/parts/drone_bits.gd")
const DroneSwarm = preload("res://scripts/parts/drone_swarm.gd")
const BulletDefault = preload("res://scenes/projectiles/bullet.tscn")
const BulletHeavy = preload("res://scenes/projectiles/bullet_heavy.tscn")
const BulletMinigun = preload("res://scenes/projectiles/bullet_minigun.tscn")
const BulletRotaryLaser = preload("res://scenes/projectiles/bullet_rotary_laser.tscn")
const BulletWave = preload("res://scenes/projectiles/bullet_wave.tscn")
const BulletLaser = preload("res://scenes/projectiles/bullet_laser.tscn")
const BulletAutoLaser = preload("res://scenes/projectiles/bullet_auto_laser.tscn")
const PlayerRocket = preload("res://scenes/projectiles/player_rocket.tscn")
const PlayerSeekingMissile = preload("res://scenes/projectiles/player_seeking_missile.tscn")

# Pool entries: [factory_callable, slot_for_factory]
# Slot is used for the WING_LEFT vs WING_RIGHT disambiguation only.
static func _all_pool() -> Array:
	return [
		{"factory": "_make_basic_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_vectoring_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_basic_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_heavy_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_machinegun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_rotary_laser", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_wave_gun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_laser_beam", "slot": Slots.SlotType.CANNON},
		# Cody 2026-05-19: missile/rocket weapons live in HARDPOINT_WING
		# now (secondary slot, fires alongside primary cannon via `shoot2`).
		{"factory": "_make_rocket_pod", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_seeking_missile", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_spread_cannon", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_smart_bomb", "slot": Slots.SlotType.DEVICE_BAY_1},
		{"factory": "_make_hyper_mode", "slot": Slots.SlotType.DEVICE_BAY_1},
		{"factory": "_make_phase_shift", "slot": Slots.SlotType.DEVICE_BAY_1},
		{"factory": "_make_particle_beam", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_side_pods", "slot": Slots.SlotType.HARDPOINT_WING},
		# Cobalt 2026-05-21: Drone Bits (secondary shield drones) sidelined
		# while the combined Drone Swarm super is the canonical drone
		# experience. Roman 2026-05-24: re-enabled — renamed to "Intercept
		# Drones" and was missing from the hangar roll pool.
		{"factory": "_make_drone_bits", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_drone_swarm", "slot": Slots.SlotType.DEVICE_BAY_1},
	]

static func roll_random_part(rng: RandomNumberGenerator):
	var pool = _all_pool()
	var entry = pool[rng.randi() % pool.size()]
	var part = _make_by_name(entry["factory"], entry["slot"])
	if part == null:
		return null
	var mark: int = 1 + (rng.randi() % 3)
	if rng.randi() % 4 == 0:
		mark += rng.randi() % 3
	mark = clampi(mark, 1, 9)
	part.mark = mark
	return part

# Roll a different part for the same slot as `existing`, at the given mark.
# Used by Junk Trader (trade same-slot, possibly different model + mark delta).
# Returns null if no alternative is available for that slot.
static func roll_for_slot(rng: RandomNumberGenerator, slot: int, mark: int):
	var candidates: Array = []
	for entry in _all_pool():
		if int(entry["slot"]) == slot:
			candidates.append(entry)
	if candidates.is_empty():
		return null
	var pick = candidates[rng.randi() % candidates.size()]
	var part = _make_by_name(pick["factory"], pick["slot"])
	if part == null:
		return null
	part.mark = clampi(mark, 1, 9)
	return part


static func _make_by_name(name: String, slot: int):
	match name:
		"_make_basic_engine":
			return BasicEngine.new()
		"_make_vectoring_engine":
			return VectoringEngine.new()
		"_make_basic_blaster":
			return _build_weapon("res://resources/weapons/energy_blaster.tres", BasicBlasterCannon, BulletDefault)
		"_make_heavy_blaster":
			return _build_weapon("res://resources/weapons/heavy_blaster.tres", HeavyBlaster, BulletHeavy)
		"_make_machinegun":
			return _build_weapon("res://resources/weapons/machinegun.tres", MachinegunCannon, BulletMinigun)
		"_make_rotary_laser":
			return _build_weapon("res://resources/weapons/rotary_laser.tres", RotaryLaserCannon, BulletRotaryLaser)
		"_make_wave_gun":
			# Bullet fallback is null — WaveGunCannon picks small vs large per
			# Mk inside apply(). Forcing a single bullet here would override
			# the Mk-based selection.
			return _build_weapon("res://resources/weapons/wave_gun.tres", WaveGunCannon, null)
		"_make_laser_beam":
			# Renamed to "Auto Laser" 2026-05-24 — alternating tandem fire,
			# uses the energy_bolt_small projectile.
			return _build_weapon("res://resources/weapons/laser_beam.tres", LaserBeamCannon, BulletAutoLaser)
		"_make_rocket_pod":
			return _build_weapon("res://resources/weapons/rocket_pod.tres", RocketPodCannon, PlayerRocket)
		"_make_seeking_missile":
			return _build_weapon("res://resources/weapons/seeking_missile.tres", SeekingMissileCannon, PlayerSeekingMissile)
		"_make_spread_cannon":
			return _build_weapon("res://resources/weapons/spread_cannon.tres", SpreadCannon, BulletDefault)
		"_make_smart_bomb":
			return _build_weapon("res://resources/weapons/smart_bomb.tres", SmartBomb, null)
		"_make_hyper_mode":
			return _build_weapon("res://resources/weapons/hyper_mode.tres", HyperMode, null)
		"_make_phase_shift":
			return _build_weapon("res://resources/weapons/phase_shift.tres", PhaseShift, null)
		"_make_particle_beam":
			return _build_weapon("res://resources/weapons/particle_beam.tres", ParticleBeam, null)
		"_make_side_pods":
			return SidePods.new()
		"_make_drone_bits":
			return _build_weapon("res://resources/weapons/drone_bits.tres", DroneBits, BulletDefault)
		"_make_drone_swarm":
			return _build_weapon("res://resources/weapons/drone_swarm.tres", DroneSwarm, null)
	return null


# Weapon-editor parity: load resources/weapons/<name>.tres if present,
# else build a fresh instance from the script. Duplicate the loaded
# resource so subsequent uses don't mutate a shared cache. Auto-assigns
# bullet_scene from the bullet fallback when the .tres didn't set it.
static func _build_weapon(tres_path: String, fallback_script: Script, bullet_fallback):
	var weapon
	if ResourceLoader.exists(tres_path):
		var loaded = load(tres_path)
		if loaded != null:
			weapon = loaded.duplicate()
	if weapon == null:
		weapon = fallback_script.new()
	# Godot does NOT call _init() on Resources loaded from disk; the .tres files
	# don't persist display_name / description / slot_type (only the stat
	# @exports). Without this, loaded weapons stay at base defaults
	# (display_name="Unnamed Part", description="", slot_type=-1). slot_type=-1
	# is the load-bearing one — it makes Run.equip_part route to slot -1, so
	# the part doesn't reach its real slot and the player can't fire it.
	if fallback_script != null:
		var defaults = fallback_script.new()
		if "display_name" in weapon and (weapon.display_name == "" or weapon.display_name == "Unnamed Part"):
			weapon.display_name = defaults.display_name
			if "description" in weapon and "description" in defaults:
				weapon.description = defaults.description
		if "slot_type" in weapon and int(weapon.slot_type) < 0 and "slot_type" in defaults:
			weapon.slot_type = defaults.slot_type
	if bullet_fallback != null and "bullet_scene" in weapon and weapon.bullet_scene == null:
		weapon.bullet_scene = bullet_fallback
	return weapon
