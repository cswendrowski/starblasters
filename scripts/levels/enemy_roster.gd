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

const SIZE_TABLE := {
	"small":  {"hp": 4,   "shield_cap": 1, "bounty": 5,   "speed_mult": 1.3},
	"medium": {"hp": 8,   "shield_cap": 2, "bounty": 15,  "speed_mult": 1.0},
	"large":  {"hp": 16,  "shield_cap": 3, "bounty": 40,  "speed_mult": 0.75},
	"huge":   {"hp": 32,  "shield_cap": 4, "bounty": 100, "speed_mult": 0.5},
	"giant":  {"hp": 64,  "shield_cap": 5, "bounty": 250, "speed_mult": 0.3},
}

const RARITY_BOUNTY_MULT := {
	Tier.COMMON: 1,
	Tier.UNCOMMON: 2,
	Tier.RARE: 4,
}

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const SCurve = preload("res://scripts/enemies/patterns/s_curve.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
const SlowAdvance = preload("res://scripts/enemies/patterns/slow_advance.gd")
const SideCut = preload("res://scripts/enemies/patterns/side_cut.gd")
const AdvanceRetreat = preload("res://scripts/enemies/patterns/advance_retreat.gd")
const SideTraverse = preload("res://scripts/enemies/patterns/side_traverse.gd")
const SidePingpong = preload("res://scripts/enemies/patterns/side_pingpong.gd")
const TopDive = preload("res://scripts/enemies/patterns/top_dive.gd")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const BulwarkDrift = preload("res://scripts/enemies/patterns/bulwark_drift.gd")

const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")
const AimedShot = preload("res://scripts/enemies/shoot_patterns/aimed_fire.gd")
const BurstShot = preload("res://scripts/enemies/shoot_patterns/burst_shot.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

# Bullet variant resources — wired per entry below.
const BV_Basic        = preload("res://data/bullets/basic.tres")
const BV_SpreadPellet = preload("res://data/bullets/spread_pellet.tres")
const BV_AimedSniper  = preload("res://data/bullets/aimed_sniper.tres")
const BV_BurstRound   = preload("res://data/bullets/burst_round.tres")
const BV_PlasmaOrb    = preload("res://data/bullets/plasma_orb.tres")

# Each entry: scene path + movement_factory + shoot_factory + tier + suggested
# counts per wave at the entry-level (modest end of the scaling).
# `shoot` may be null for melee/contact enemies.
#
# Optional gating fields (Cody 2026-05-23, chaff rework):
#   unlock_sector: int — entry only eligible when sector_idx >= this (default 1)
#   unlock_depth:  int — entry only eligible when sector_depth >= this (default 1)
#   weight:        float — relative pool weight (default 1.0)
#   hp_override / bounty_override — explicit stat overrides for compose_stats
const ENTRIES := [
	# --- COMMON -----------------------------------------------------------
	{
		"scene": "res://scenes/enemies/enemy_firecore.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "firecore_straight",
		"shoot": "single_diagonal",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 6,
		# Fire-rate pass (2026-05-30, Roman): chaff was firing every ~2.0-3.5s
		# and felt passive. Tightened to ~1.4-2.3s (~35% faster) so firecore
		# reads as active without becoming a wall. Keeps min<max jitter so
		# volleys desync. First-pass — tune in playtest.
		"fire_min": 1.4, "fire_max": 2.3,
		"unlock_sector": 2, "unlock_depth": 5, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/enemy_dart.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 1.4, "chaff": true,
	},
	{
		"scene": "res://scenes/enemies/enemy_bomb_drone.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 2, "weight": 1.0, "chaff": true,
	},
	{
		"scene": "res://scenes/enemies/enemy_drifter.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "drifter_straight",
		"shoot": "single_diagonal",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 4,
		# Fire-rate pass (2026-05-30, Roman): was ~2.4-3.2s (slowest shooter).
		# Tightened to ~1.6-2.2s (~33% faster). Drifter stays a touch slower
		# than firecore so the two chaff types still feel distinct. First-pass.
		"fire_min": 1.6, "fire_max": 2.2,
		"hp_override": 1, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 2, "weight": 1.2, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},
	{
		"scene": "res://scenes/enemies/enemy_hunter_drone.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "beeline",
		"shoot": null,
		"base_count": 4,
		# Hunter Drones are kamikaze threats, not bounty piñatas — pay
		# mine-equivalent value (1) so killing one doesn't reward more
		# than dodging an asteroid/mine of the same threat profile.
		"bounty_override": 1,
		"unlock_sector": 2, "unlock_depth": 4, "weight": 0.6, "chaff": true,
	},

	# --- UNCOMMON ---------------------------------------------------------
	{
		# Burner — beam pair (Roman, 2026-05-31). Bespoke self-driving enemy:
		# arrives in pairs, strings a damaging beam between the two members and
		# descends together; killing either blows up both. Handles its own
		# movement + beam (no Resource slots) so movement/shoot are null, like
		# enemy_firecore_cruiser. NOT chaff-rolled — spawned only by explicit
		# wave authoring. Burner waves MUST use formation TOP_TANDEM_PAIRS
		# (index 5) and an EVEN count so every member gets a partner; an odd
		# member simply descends and leaves (no beam) rather than crashing.
		"scene": "res://scenes/enemies/enemy_burner.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": null,   # handles own movement
		"shoot": null,      # handles own beam
		"base_count": 2,
		"hp_override": 12, "bounty_override": 30,
	},
	{
		"scene": "res://scenes/enemies/enemy_weaver.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "s_curve",
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		"base_count": 2,
		"fire_min": 1.4, "fire_max": 2.2,
		"hp_override": 2, "bounty_override": 10,
		"unlock_sector": 1, "unlock_depth": 4, "weight": 0.9, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "wide_dodge"],
	},
	{
		"scene": "res://scenes/enemies/enemy_hover.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "loiter",
		"shoot": "single",
		"bullet_variant": BV_Basic,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.9, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	{
		"scene": "res://scenes/enemies/enemy_frigate.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "slow_advance",
		"shoot": "burst",
		"bullet_variant": BV_BurstRound,
		"base_count": 3,
		# Fire-rate pass (2026-05-30, Roman): workhorse gunner — pulled the
		# slow ceiling in from 2.8 → 2.4s so the 3-round burst recurs a bit
		# more often. Floor unchanged (burst is already a heavy beat). First-pass.
		"fire_min": 1.8, "fire_max": 2.4,
	},
	# TODO: Replace cutter with a new horizontal strafe enemy that crosses the screen cleanly
	#{
	#	"scene": "res://scenes/enemies/enemy_cutter.tscn",
	#	"tier": Tier.UNCOMMON,
	#	"size": "small", "tags": [],
	#	"movement": "side_cut",
	#	"shoot": "single_fast",
	#	"base_count": 4,
	#	"fire_min": 0.3, "fire_max": 0.5,
	#	"hp_override": 1, "bounty_override": 10,
	#	"unlock_sector": 1, "unlock_depth": 4, "weight": 1.0, "chaff": true,
	#	"conflict_tags": ["dumb_shot"],
	#},
	{
		"scene": "res://scenes/enemies/enemy_skirmisher.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "advance_retreat",
		"shoot": "aimed",
		"bullet_variant": BV_AimedSniper,
		"base_count": 3,
		"fire_min": 0.7, "fire_max": 1.1,
		"hp_override": 2, "bounty_override": 15,
		"unlock_sector": 2, "unlock_depth": 3, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},

	{
		"scene": "res://scenes/enemies/enemy_beam_shooter.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "loiter",
		"shoot": null,  # uses built-in beam, not shoot_pattern
		"base_count": 2,
		"conflict_tags": ["beamshooter"],
	},
	# Gunship single: one ship sweeps left↔right, fires 3 salvos, exits.
	{
		"scene": "res://scenes/enemies/enemy_gunship.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "loiter",
		"shoot": null,
		"base_count": 1,
		"no_scale": true,  # count must stay fixed; role logic requires exact N
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8,
	},
	# Gunship duo: two ships sweep in opposite directions.
	{
		"scene": "res://scenes/enemies/enemy_gunship.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "loiter",
		"shoot": null,
		"base_count": 2,
		"no_scale": true,  # exact 2
		"unlock_sector": 2, "unlock_depth": 2, "weight": 0.9,
	},
	# Gunship trio: three ships in fixed spread formation.
	{
		"scene": "res://scenes/enemies/enemy_gunship.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "loiter",
		"shoot": null,
		"base_count": 3,
		"no_scale": true,  # exact 3
		"unlock_sector": 3, "unlock_depth": 2, "weight": 0.7,
	},

	# --- RARE -------------------------------------------------------------
	{
		"scene": "res://scenes/enemies/enemy_sapper.tscn",
		"tier": Tier.RARE,
		"size": "small", "tags": [],
		"movement": "omni",
		"shoot": null,
		"base_count": 1,
	},
	{
		"scene": "res://scenes/enemies/enemy_crystal.tscn",
		"tier": Tier.RARE,
		"size": "medium", "tags": [],
		"movement": "loiter",
		"shoot": "spread5",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 2,
		"fire_min": 1.8, "fire_max": 2.6,
	},
	{
		"scene": "res://scenes/enemies/enemy_minelayer.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "side_traverse",
		"shoot": null,
		"base_count": 2,
	},
	{
		"scene": "res://scenes/enemies/enemy_interceptor.tscn",
		"tier": Tier.RARE,
		"size": "medium", "tags": ["tough"],
		"movement": "top_dive",
		"shoot": null,
		"base_count": 3,
	},
	{
		"scene": "res://scenes/enemies/enemy_bulwark.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "bulwark_drift",
		"shoot": null,
		"base_count": 1,
	},
	{
		"scene": "res://scenes/enemies/enemy_cruiser.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "loiter",
		"shoot": null,
		"base_count": 1,
	},
	{
		"scene": "res://scenes/enemies/enemy_drone_carrier.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "loiter",
		"shoot": null,
		"base_count": 1,
	},
	{
		"scene": "res://scenes/enemies/enemy_firecore_cruiser.tscn",
		"tier": Tier.RARE,
		"size": "huge", "tags": ["tough"],
		"movement": null,   # handles own movement
		"shoot": null,      # handles own shooting
		"base_count": 1,
		"no_scale": true,
		"hp_override": 32, "bounty_override": 100,
		"unlock_sector": 2, "unlock_depth": 6, "weight": 0.6,
	},
	{
		# Firecore Drone (Roman, 2026-05-31). Small + tough; descends slowly
		# wreathed in 1-4 concentric rings of orbiting bullet visuals. Doesn't
		# shoot — killing it DETACHES the rings into real enemy_bullets that fly
		# outward as expanding waves. Bespoke self-driving enemy (handles its own
		# descent + ring orbit + death release), so movement/shoot are null like
		# burner/firecore_cruiser. NOT chaff-rolled — spawned only by explicit
		# wave authoring (build_firecore_drone_showcase). Keep hp_override in sync
		# with the script's max_health (10) so the codex matches.
		"scene": "res://scenes/enemies/enemy_firecore_drone.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": null,   # handles own movement
		"shoot": null,      # handles own ring release
		"base_count": 3,
		"hp_override": 10, "bounty_override": 25,
	},
]


# Returns a weighted pool of scene paths eligible at the given sector + depth.
# Each path appears `round(weight * 10)` times so the existing
# `pool[randi() % pool.size()]` selection respects per-entry weights.
# Only entries explicitly opted into chaff rolls via `chaff: true` are picked —
# specialized enemies (beam_shooter, gunship, cruiser, drone_carrier, burner,
# sapper) are roster-listed for stats/codex but not chaff-rolled.
static func eligible_pool(sector_idx: int, sector_depth: int, tier_max: int) -> Array:
	var pool: Array = []
	for e in ENTRIES:
		if not bool(e.get("chaff", false)):
			continue
		if int(e.get("tier", Tier.COMMON)) > tier_max:
			continue
		if int(e.get("unlock_sector", 1)) > sector_idx:
			continue
		if int(e.get("unlock_depth", 1)) > sector_depth:
			continue
		var weight: float = float(e.get("weight", 1.0))
		var copies: int = max(1, int(round(weight * 10.0)))
		for _i in copies:
			pool.append(str(e["scene"]))
	return pool


static func entries_of(tier: int) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if int(e["tier"]) == tier:
			out.append(e)
	return out


static func entry_for_scene(scene_path: String) -> Dictionary:
	for e in ENTRIES:
		if str(e["scene"]) == scene_path:
			return e
	return {}


static func compose_stats(entry: Dictionary) -> Dictionary:
	var size: String = entry.get("size", "medium")
	var st: Dictionary = SIZE_TABLE.get(size, SIZE_TABLE["medium"])
	var tags: Array = entry.get("tags", [])
	var tier: int = int(entry.get("tier", Tier.COMMON))

	var hp: int = st["hp"]
	if "tough" in tags:
		hp *= 2
	if entry.has("hp_override"):
		hp = int(entry["hp_override"])

	var shield_charges: int = 0
	if "shielded" in tags:
		shield_charges = st["shield_cap"]
		if "tough" in tags:
			shield_charges *= 2

	var bounty: int = st["bounty"] * RARITY_BOUNTY_MULT.get(tier, 1)
	if entry.has("bounty_override"):
		bounty = int(entry["bounty_override"])
	var recycle: int = entry.get("recycle", -2)
	if recycle >= 0:
		bounty = max(1, int(round(float(bounty) * max(0.5, 1.0 - 0.15 * float(recycle)))))

	return {
		"max_health": hp,
		"shield_charges": shield_charges,
		"bounty_value": bounty,
		"recycle_passes": recycle,
	}


# Build a fresh movement-pattern Resource for an entry. Each spawned enemy
# duplicates this so the pattern can keep per-instance state.
static func make_movement(entry: Dictionary) -> Resource:
	match entry.get("movement", "straight"):
		"straight":
			# Generic chaff descent (Burner). Firecore + Drifter have their
			# own keys after the 2026-05-24 speed pass.
			var m = StraightDown.new()
			m.speed = 220.0
			return m
		"firecore_straight":
			# Firecore — slowed from 220 to 180 so it sits between Drifter
			# (110) and the dive tier (Dart 360). Mid-band fodder.
			var m = StraightDown.new()
			m.speed = 180.0
			return m
		"drifter_straight":
			# Drifter — slow descent (110) with ±15 lateral drift so it
			# doesn't read as a Firecore clone. TOS ~2.5s.
			var m = StraightDown.new()
			m.speed = 110.0
			m.drift_x = 15.0 if randf() < 0.5 else -15.0
			return m
		"fast_straight":
			# Dart — 360 (was 480). 480 reaction-test variant is filed as a
			# separate "Sprint Dart" TODO in TODO.md.
			var m = StraightDown.new()
			m.speed = 360.0
			return m
		"s_curve":
			# Weaver carries aimed fire — slow carriage so the player can
			# read the lead. 220→160 down, freq 1.6→1.2, amp 160→110.
			var m = SCurve.new()
			m.down_speed = 160.0
			m.amplitude = 110.0
			m.frequency = 1.2
			return m
		"loiter":
			# Hover etc. Exit accel/max trimmed (was 600/700) so a player
			# drifting upward isn't rammed by an exiting Hover.
			var m = Loiter.new()
			m.hover_y = 240.0
			m.enter_speed = 180.0
			m.loiter_time = 3.0
			m.exit_accel = 400.0
			m.exit_max_speed = 480.0
			return m
		"slow_advance":
			# Frigate — enter_speed 35→60 so it actually reaches hold_y
			# before the player kills it.
			var m = SlowAdvance.new()
			m.enter_speed = 60.0
			return m
		"side_cut":
			# Cutter — identity is "snaps across screen". 130→160 enter,
			# 210→250 cut.
			var m = SideCut.new()
			m.enter_speed = 160.0
			m.cut_speed = 250.0
			m.direction = 1 if randf() < 0.5 else -1
			return m
		"advance_retreat":
			# Skirmisher — aimed-fire pacing slowed. 180→150 adv, 260→220
			# ret, 0.6→0.8 hold.
			var m = AdvanceRetreat.new()
			m.advance_speed = 150.0
			m.retreat_speed = 220.0
			m.hold_time = 0.8
			return m
		"side_traverse":
			# Minelayer — 55→75 so TOS is ~6s instead of ~9s.
			var m = SideTraverse.new()
			m.speed = 75.0
			m.direction = 1 if randf() < 0.5 else -1
			return m
		"top_dive":
			# Interceptor — 270→220 to differentiate from Dart by trajectory,
			# not raw speed.
			var m = TopDive.new()
			m.speed = 220.0
			return m
		"beeline":
			# Hunter Drone — should threaten, not connect. 230→190 hunt,
			# 360→280 accel.
			var m = BeelinePlayer.new()
			m.max_speed = 190.0
			m.accel = 280.0
			return m
		"bulwark_drift":
			# Bulwark drift is out of scope here — separate Bulwark turret
			# task will retune it.
			return BulwarkDrift.new()
	return StraightDown.new()


static func make_shoot(entry: Dictionary) -> Resource:
	var kind: Variant = entry.get("shoot", null)
	if kind == null:
		return null
	var pattern: Resource = null
	match kind:
		"single":
			var s = SingleShot.new()
			s.bullet_scene = EnemyBullet
			pattern = s
		"single_fast":
			var s = SingleShot.new()
			s.bullet_scene = EnemyBullet
			pattern = s
		"single_diagonal":
			# Fires toward the opposite side — left-spawn enemies angle right,
			# right-spawn enemies angle left. ~30° diagonal.
			var s = SingleShot.new()
			s.bullet_scene = EnemyBullet
			s.aim_angle_deg = 30.0
			s.aim_toward_center = true
			pattern = s
		"aimed":
			var s = AimedShot.new()
			s.bullet_scene = EnemyBullet
			pattern = s
		"burst":
			var s = BurstShot.new()
			s.bullet_scene = EnemyBullet
			s.burst_count = 3
			s.burst_interval = 0.18
			pattern = s
		"spread5":
			var s = SpreadShot.new()
			s.bullet_scene = EnemyBullet
			s.bullet_count = 5
			s.spread_degrees = 36.0
			pattern = s
	if pattern != null:
		pattern.bullet_variant = entry.get("bullet_variant", null)
	return pattern
