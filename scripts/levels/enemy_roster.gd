extends RefCounted
class_name EnemyRoster

# Roster of every combat enemy with a rarity tier and the patterns that go
# with it. The dynamic wave generator pulls from this table, weighted by
# rarity and the depth into the current sector.
#
# Rarity rules of thumb:
#   COMMON   — chaff: 1 HP, low bounty, simple straight-down or contact role
#   UNCOMMON — workhorse: 2-3 HP, sub-pattern (advance/retreat, burst), 15-30 bounty
#   RARE     — elite: 4+ HP OR uniquely disruptive ability, 35+ bounty
#
# Mine/asteroid scenes are deliberately excluded — those are hazards, not
# wave fodder.

enum Tier { COMMON, UNCOMMON, RARE }

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const SCurve = preload("res://scripts/enemies/patterns/s_curve.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
const SlowAdvance = preload("res://scripts/enemies/patterns/slow_advance.gd")
const SideCut = preload("res://scripts/enemies/patterns/side_cut.gd")
const AdvanceRetreat = preload("res://scripts/enemies/patterns/advance_retreat.gd")
const SideTraverse = preload("res://scripts/enemies/patterns/side_traverse.gd")
const TopDive = preload("res://scripts/enemies/patterns/top_dive.gd")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const BulwarkDrift = preload("res://scripts/enemies/patterns/bulwark_drift.gd")

const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")
const AimedShot = preload("res://scripts/enemies/shoot_patterns/aimed_fire.gd")
const BurstShot = preload("res://scripts/enemies/shoot_patterns/burst_shot.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

# Each entry: scene path + movement_factory + shoot_factory + tier + suggested
# counts per wave at the entry-level (modest end of the scaling).
# `shoot` may be null for melee/contact enemies.
const ENTRIES := [
	# --- COMMON -----------------------------------------------------------
	{
		"scene": "res://scenes/enemies/enemy_firecore.tscn",
		"tier": Tier.COMMON,
		"movement": "straight",
		"shoot": "single",
		"base_count": 6,
		"fire_min": 2.0, "fire_max": 3.5,
		"max_health": 1, "bounty_value": 5,
	},
	{
		"scene": "res://scenes/enemies/enemy_diver.tscn",
		"tier": Tier.COMMON,
		"movement": "fast_straight",
		"shoot": "single",
		"base_count": 7,
		"fire_min": 0.7, "fire_max": 1.3,
		"max_health": 1, "bounty_value": 5,
	},
	{
		"scene": "res://scenes/enemies/enemy_dart.tscn",
		"tier": Tier.COMMON,
		"movement": "s_curve",
		"shoot": "aimed",
		"base_count": 5,
		"fire_min": 1.2, "fire_max": 2.0,
		"max_health": 2, "bounty_value": 15,
	},
	{
		"scene": "res://scenes/enemies/enemy_hunter_drone.tscn",
		"tier": Tier.COMMON,
		"movement": "beeline",
		"shoot": null,
		"base_count": 4,
		"max_health": 1, "bounty_value": 10,
	},

	# --- UNCOMMON ---------------------------------------------------------
	{
		"scene": "res://scenes/enemies/enemy_hopper.tscn",
		"tier": Tier.UNCOMMON,
		"movement": "loiter",
		"shoot": "burst",
		"base_count": 4,
		"fire_min": 1.6, "fire_max": 2.4,
		"max_health": 2, "bounty_value": 20,
	},
	{
		"scene": "res://scenes/enemies/enemy_frigate.tscn",
		"tier": Tier.UNCOMMON,
		"movement": "slow_advance",
		"shoot": "burst",
		"base_count": 3,
		"fire_min": 1.8, "fire_max": 2.8,
		"max_health": 4, "bounty_value": 25,
	},
	{
		"scene": "res://scenes/enemies/enemy_cutter.tscn",
		"tier": Tier.UNCOMMON,
		"movement": "side_cut",
		"shoot": "single_fast",
		"base_count": 4,
		"fire_min": 0.3, "fire_max": 0.5,
		"max_health": 2, "bounty_value": 30,
	},
	{
		"scene": "res://scenes/enemies/enemy_skirmisher.tscn",
		"tier": Tier.UNCOMMON,
		"movement": "advance_retreat",
		"shoot": "aimed",
		"base_count": 4,
		"fire_min": 0.7, "fire_max": 1.1,
		"max_health": 2, "bounty_value": 25,
	},

	# --- RARE -------------------------------------------------------------
	{
		"scene": "res://scenes/enemies/enemy_crystal.tscn",
		"tier": Tier.RARE,
		"movement": "loiter",
		"shoot": "spread5",
		"base_count": 2,
		"fire_min": 1.8, "fire_max": 2.6,
		"max_health": 3, "bounty_value": 25,
	},
	{
		"scene": "res://scenes/enemies/enemy_minelayer.tscn",
		"tier": Tier.RARE,
		"movement": "side_traverse",
		"shoot": null,
		"base_count": 2,
		"max_health": 4, "bounty_value": 40,
	},
	{
		"scene": "res://scenes/enemies/enemy_interceptor.tscn",
		"tier": Tier.RARE,
		"movement": "top_dive",
		"shoot": null,
		"base_count": 3,
		"max_health": 2, "bounty_value": 35,
	},
	{
		"scene": "res://scenes/enemies/enemy_bulwark.tscn",
		"tier": Tier.RARE,
		"movement": "bulwark_drift",
		"shoot": null,
		"base_count": 1,
		"max_health": 5, "bounty_value": 50,
	},
]


static func entries_of(tier: int) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if int(e["tier"]) == tier:
			out.append(e)
	return out


# Build a fresh movement-pattern Resource for an entry. Each spawned enemy
# duplicates this so the pattern can keep per-instance state.
static func make_movement(entry: Dictionary) -> Resource:
	match entry.get("movement", "straight"):
		"straight":
			var m = StraightDown.new()
			m.speed = 220.0
			return m
		"fast_straight":
			var m = StraightDown.new()
			m.speed = 480.0
			return m
		"s_curve":
			var m = SCurve.new()
			m.down_speed = 220.0
			m.amplitude = 160.0
			m.frequency = 1.6
			return m
		"loiter":
			var m = Loiter.new()
			m.hover_y = 240.0
			m.enter_speed = 240.0
			m.loiter_time = 5.0
			m.exit_accel = 600.0
			m.exit_max_speed = 700.0
			return m
		"slow_advance":
			return SlowAdvance.new()
		"side_cut":
			var m = SideCut.new()
			m.direction = 1 if randf() < 0.5 else -1
			return m
		"advance_retreat":
			return AdvanceRetreat.new()
		"side_traverse":
			var m = SideTraverse.new()
			m.direction = 1 if randf() < 0.5 else -1
			return m
		"top_dive":
			return TopDive.new()
		"beeline":
			return BeelinePlayer.new()
		"bulwark_drift":
			return BulwarkDrift.new()
	return StraightDown.new()


static func make_shoot(entry: Dictionary) -> Resource:
	var kind: Variant = entry.get("shoot", null)
	if kind == null:
		return null
	match kind:
		"single":
			var s = SingleShot.new()
			s.bullet_scene = EnemyBullet
			return s
		"single_fast":
			var s = SingleShot.new()
			s.bullet_scene = EnemyBullet
			return s
		"aimed":
			var s = AimedShot.new()
			s.bullet_scene = EnemyBullet
			return s
		"burst":
			var s = BurstShot.new()
			s.bullet_scene = EnemyBullet
			s.burst_count = 3
			s.burst_interval = 0.18
			return s
		"spread5":
			var s = SpreadShot.new()
			s.bullet_scene = EnemyBullet
			s.bullet_count = 5
			s.spread_degrees = 36.0
			return s
	return null
