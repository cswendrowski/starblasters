extends Node

# Catalog of every available part with a rolling-pool API for outposts.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const BasicEngine = preload("res://scripts/parts/basic_engine.gd")
const BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const HeavyBlaster = preload("res://scripts/parts/heavy_blaster.gd")
const VectoringEngine = preload("res://scripts/parts/vectoring_engine.gd")
const AutocannonCannon = preload("res://scripts/parts/autocannon_cannon.gd")
const MinigunCannon = preload("res://scripts/parts/minigun_cannon.gd")
const RotaryLaserCannon = preload("res://scripts/parts/rotary_laser_cannon.gd")
const WaveGunCannon = preload("res://scripts/parts/wave_gun_cannon.gd")
const LaserBeamCannon = preload("res://scripts/parts/laser_beam_cannon.gd")
const RocketPodCannon = preload("res://scripts/parts/rocket_pod_cannon.gd")
const SeekingMissileCannon = preload("res://scripts/parts/seeking_missile_cannon.gd")
const AntiShipMissileCannon = preload("res://scripts/parts/anti_ship_missile_cannon.gd")
const EmTorpedoCannon = preload("res://scripts/parts/em_torpedo_cannon.gd")
const SpreadCannon = preload("res://scripts/parts/spread_cannon.gd")
const SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
# Shift-Mode parts (SHIFT_MODE slot) — Focus is the default; Phase/Hyper swap in.
const FocusMode = preload("res://scripts/parts/focus_mode.gd")
const HyperMode = preload("res://scripts/parts/hyper_mode.gd")
const PhaseShift = preload("res://scripts/parts/phase_shift.gd")
const ParticleBeam = preload("res://scripts/parts/particle_beam.gd")
const SidePods = preload("res://scripts/parts/side_pods.gd")
const DroneBits = preload("res://scripts/parts/drone_bits.gd")
const DroneSwarm = preload("res://scripts/parts/drone_swarm.gd")
const SwarmLauncher = preload("res://scripts/parts/swarm_launcher.gd")
const BulletDefault = preload("res://scenes/projectiles/bullet_blaster.tscn")
const BulletHeavy = preload("res://scenes/projectiles/bullet_blaster_heavy.tscn")
const BulletMinigun = preload("res://scenes/projectiles/bullet_minigun.tscn")
const BulletAutocannon = preload("res://scenes/projectiles/bullet_autocannon.tscn")
const BulletRotaryLaser = preload("res://scenes/projectiles/bullet_rotary_laser.tscn")
const BulletWave = preload("res://scenes/projectiles/bullet_wave.tscn")
const BulletMedium = preload("res://scenes/projectiles/bullet_blaster_medium.tscn")
const BulletAutoLaser = preload("res://scenes/projectiles/bullet_auto_laser.tscn")
const PlayerRocket = preload("res://scenes/projectiles/player_rocket.tscn")
const PlayerSeekingMissile = preload("res://scenes/projectiles/player_seeking_missile.tscn")
const PlayerSeekingMissileLarge = preload("res://scenes/projectiles/player_seeking_missile_large.tscn")
const PlayerEmTorpedo = preload("res://scenes/projectiles/player_em_torpedo.tscn")
const PlayerSwarmMissile = preload("res://scenes/projectiles/bullet_swarm.tscn")

# Pool entries: [factory_callable, slot_for_factory]
# Slot is used for the WING_LEFT vs WING_RIGHT disambiguation only.
static func _all_pool() -> Array:
	return [
		{"factory": "_make_basic_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_vectoring_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_basic_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_heavy_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_autocannon", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_minigun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_rotary_laser", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_wave_gun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_laser_beam", "slot": Slots.SlotType.CANNON},
		# Cody 2026-05-19: missile/rocket weapons live in HARDPOINT_WING
		# now (secondary slot, fires alongside primary cannon via `shoot2`).
		{"factory": "_make_rocket_pod", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_seeking_missile", "slot": Slots.SlotType.HARDPOINT_WING},
		# Roman 2026-05-30: Anti-Ship Missile — heavy secondary, large slow
		# projectile, prefers/one-shots the largest enemy, half ammo.
		{"factory": "_make_anti_ship_missile", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_spread_cannon", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_smart_bomb", "slot": Slots.SlotType.DEVICE_BAY_1},
		# Shift-Mode swap-ins (SHIFT_MODE slot, on Shift). Focus is the default
		# mode (equipped at run start), so it is NOT in the roll/shop pool.
		{"factory": "_make_phase_shift", "slot": Slots.SlotType.SHIFT_MODE},
		{"factory": "_make_hyper_mode", "slot": Slots.SlotType.SHIFT_MODE},
		{"factory": "_make_particle_beam", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_side_pods", "slot": Slots.SlotType.HARDPOINT_WING},
		# Cobalt 2026-05-21: Drone Bits (secondary shield drones) sidelined
		# while the combined Drone Swarm super is the canonical drone
		# experience. Roman 2026-05-24: re-enabled — renamed to "Intercept
		# Drones" and was missing from the hangar roll pool.
		{"factory": "_make_drone_bits", "slot": Slots.SlotType.HARDPOINT_WING},
		# Roman 2026-05-30: Combat Drones converted SUPER -> SECONDARY; now
		# equips in the HARDPOINT_WING slot and fires on shoot2 (deploy).
		{"factory": "_make_drone_swarm", "slot": Slots.SlotType.HARDPOINT_WING},
		{"factory": "_make_swarm_launcher", "slot": Slots.SlotType.HARDPOINT_WING},
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
	mark = clampi(mark, 1, part.max_mark)
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
	part.mark = clampi(mark, 1, part.max_mark)
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
		"_make_autocannon":
			# Autocannon fires its OWN projectile, bullet_autocannon.tscn (Roman 2026-06-10 rename;
			# distinct from the minigun's). The old AutocannonCannon.new() left bullet_scene null so
			# the ship kept the BLASTER bullet; _build_weapon's fallback assigns the right one.
			return _build_weapon("res://resources/weapons/autocannon.tres", AutocannonCannon, BulletAutocannon)
		"_make_minigun":
			return _build_weapon("res://resources/weapons/minigun.tres", MinigunCannon, BulletMinigun)
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
		"_make_anti_ship_missile":
			return _build_weapon("res://resources/weapons/anti_ship_missile.tres", AntiShipMissileCannon, PlayerSeekingMissileLarge)
		"_make_em_torpedo":
			# No .tres yet (test-only weapon, not in the shop pool) — _build_weapon falls back to the
			# script. Deliberately ABSENT from _all_pool() so it can't roll in live runs (Roman
			# 2026-06-10: ship behind the dev Test-Combat entry until the wreck layer is validated).
			return _build_weapon("res://resources/weapons/em_torpedo.tres", EmTorpedoCannon, PlayerEmTorpedo)
		"_make_spread_cannon":
			return _build_weapon("res://resources/weapons/spread_cannon.tres", SpreadCannon, BulletDefault)
		"_make_smart_bomb":
			return _build_weapon("res://resources/weapons/smart_bomb.tres", SmartBomb, null)
		# Mode parts are pure-script (no .tres) — their stats are code-authored
		# Mk getters, not weapon-editor .tres fields.
		"_make_focus_mode":
			return FocusMode.new()
		"_make_hyper_mode":
			return HyperMode.new()
		"_make_phase_shift":
			return PhaseShift.new()
		"_make_particle_beam":
			return _build_weapon("res://resources/weapons/particle_beam.tres", ParticleBeam, null)
		"_make_side_pods":
			return SidePods.new()
		"_make_drone_bits":
			return _build_weapon("res://resources/weapons/drone_bits.tres", DroneBits, BulletDefault)
		"_make_drone_swarm":
			return _build_weapon("res://resources/weapons/drone_swarm.tres", DroneSwarm, null)
		"_make_swarm_launcher":
			return _build_weapon("res://resources/weapons/swarm_launcher.tres", SwarmLauncher, PlayerSwarmMissile)
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
