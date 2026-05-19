extends Node

# Catalog of every available part with a rolling-pool API for outposts.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const BasicWings = preload("res://scripts/parts/basic_wings.gd")
const BasicTail = preload("res://scripts/parts/basic_tail.gd")
const BasicEngine = preload("res://scripts/parts/basic_engine.gd")
const BasicShield = preload("res://scripts/parts/basic_shield.gd")
const BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const ReactiveWings = preload("res://scripts/parts/reactive_wings.gd")
const ArmoredWings = preload("res://scripts/parts/armored_wings.gd")
const QuickResetShield = preload("res://scripts/parts/quick_reset_shield.gd")
const ReinforcedShield = preload("res://scripts/parts/reinforced_shield.gd")
const HeavyBlaster = preload("res://scripts/parts/heavy_blaster.gd")
const VectoringEngine = preload("res://scripts/parts/vectoring_engine.gd")
const MachinegunCannon = preload("res://scripts/parts/machinegun_cannon.gd")
const WaveGunCannon = preload("res://scripts/parts/wave_gun_cannon.gd")
const LaserBeamCannon = preload("res://scripts/parts/laser_beam_cannon.gd")
const RocketPodCannon = preload("res://scripts/parts/rocket_pod_cannon.gd")
const SeekingMissileCannon = preload("res://scripts/parts/seeking_missile_cannon.gd")
const BulletDefault = preload("res://scenes/projectiles/bullet.tscn")
const BulletHeavy = preload("res://scenes/projectiles/bullet_heavy.tscn")
const BulletMinigun = preload("res://scenes/projectiles/bullet_minigun.tscn")
const BulletWave = preload("res://scenes/projectiles/bullet_wave.tscn")
const BulletLaser = preload("res://scenes/projectiles/bullet_laser.tscn")
const PlayerRocket = preload("res://scenes/projectiles/player_rocket.tscn")
const PlayerSeekingMissile = preload("res://scenes/projectiles/player_seeking_missile.tscn")

# Pool entries: [factory_callable, slot_for_factory]
# Slot is used for the WING_LEFT vs WING_RIGHT disambiguation only.
static func _all_pool() -> Array:
	return [
		{"factory": "_make_basic_wing", "slot": Slots.SlotType.WING_LEFT},
		{"factory": "_make_basic_wing", "slot": Slots.SlotType.WING_RIGHT},
		{"factory": "_make_reactive_wing", "slot": Slots.SlotType.WING_LEFT},
		{"factory": "_make_reactive_wing", "slot": Slots.SlotType.WING_RIGHT},
		{"factory": "_make_armored_wing", "slot": Slots.SlotType.WING_LEFT},
		{"factory": "_make_armored_wing", "slot": Slots.SlotType.WING_RIGHT},
		{"factory": "_make_basic_tail", "slot": Slots.SlotType.TAIL},
		{"factory": "_make_basic_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_vectoring_engine", "slot": Slots.SlotType.ENGINE},
		{"factory": "_make_basic_shield", "slot": Slots.SlotType.SHIELD},
		{"factory": "_make_quick_reset_shield", "slot": Slots.SlotType.SHIELD},
		{"factory": "_make_reinforced_shield", "slot": Slots.SlotType.SHIELD},
		{"factory": "_make_basic_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_heavy_blaster", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_machinegun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_wave_gun", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_laser_beam", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_rocket_pod", "slot": Slots.SlotType.CANNON},
		{"factory": "_make_seeking_missile", "slot": Slots.SlotType.CANNON},
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
		"_make_basic_wing":
			var p = BasicWings.new()
			p.slot_type = slot
			return p
		"_make_reactive_wing":
			var p = ReactiveWings.new()
			p.slot_type = slot
			return p
		"_make_armored_wing":
			var p = ArmoredWings.new()
			p.slot_type = slot
			return p
		"_make_basic_tail":
			return BasicTail.new()
		"_make_basic_engine":
			return BasicEngine.new()
		"_make_vectoring_engine":
			return VectoringEngine.new()
		"_make_basic_shield":
			return BasicShield.new()
		"_make_quick_reset_shield":
			return QuickResetShield.new()
		"_make_reinforced_shield":
			return ReinforcedShield.new()
		"_make_basic_blaster":
			var b = BasicBlasterCannon.new()
			b.bullet_scene = BulletDefault
			return b
		"_make_heavy_blaster":
			var h = HeavyBlaster.new()
			h.bullet_scene = BulletHeavy
			return h
		"_make_machinegun":
			var m = MachinegunCannon.new()
			m.bullet_scene = BulletMinigun
			return m
		"_make_wave_gun":
			var w = WaveGunCannon.new()
			w.bullet_scene = BulletWave
			return w
		"_make_laser_beam":
			var l = LaserBeamCannon.new()
			l.bullet_scene = BulletLaser
			return l
		"_make_rocket_pod":
			var r = RocketPodCannon.new()
			r.bullet_scene = PlayerRocket
			return r
		"_make_seeking_missile":
			var s = SeekingMissileCannon.new()
			s.bullet_scene = PlayerSeekingMissile
			return s
	return null
