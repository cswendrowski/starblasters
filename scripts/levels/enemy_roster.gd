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

# Size→stats (tuned in the Enemy Bench Sizes tab, intaken 2026-06-17). Bounty is now a clean
# 1/2/4/8/16/32 doubling (was 3/5/15/40/100/250 — a much steeper curve); speeds slowed a touch on
# the big classes; tiny is now 1 HP + a shield charge. NOTE: this is a sizeable economy change.
const SIZE_TABLE := {
	"tiny":   {"hp": 1,  "shield_cap": 1, "bounty": 1,  "speed_mult": 1.0},
	"small":  {"hp": 4,  "shield_cap": 1, "bounty": 2,  "speed_mult": 1.3},
	"medium": {"hp": 8,  "shield_cap": 2, "bounty": 4,  "speed_mult": 0.8},
	"large":  {"hp": 16, "shield_cap": 3, "bounty": 8,  "speed_mult": 0.6},
	"huge":   {"hp": 32, "shield_cap": 4, "bounty": 16, "speed_mult": 0.4},
	"giant":  {"hp": 64, "shield_cap": 5, "bounty": 32, "speed_mult": 0.25},
}

const RARITY_BOUNTY_MULT := {
	Tier.COMMON: 1,
	Tier.UNCOMMON: 2,
	Tier.RARE: 4,
}

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const SideTraverse = preload("res://scripts/enemies/patterns/side_traverse.gd")
const SideTurn = preload("res://scripts/enemies/patterns/side_turn.gd")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const Drift = preload("res://scripts/enemies/patterns/drift.gd")
const Skirmish = preload("res://scripts/enemies/patterns/skirmish.gd")
const LanePath = preload("res://scripts/enemies/patterns/lane_path.gd")
const OmniThrust = preload("res://scripts/enemies/patterns/omni_thrust.gd")
const LaneCharge = preload("res://scripts/enemies/patterns/lane_charge.gd")
const Pendulum = preload("res://scripts/enemies/patterns/pendulum.gd")
const ProximityChase = preload("res://scripts/enemies/patterns/proximity_chase.gd")
const LoiterSweep = preload("res://scripts/enemies/patterns/loiter_sweep.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const MountSpec = preload("res://scripts/enemies/mounts/mount_spec.gd")
const Factions = preload("res://scripts/levels/factions.gd")

# Faction pool filter (M6b): set by WaveGen.build for the duration of one generation so
# the eligibility pools draw only enemies allowed in the active faction (universal OR
# home == faction). -1 = no filter. Scoped to a single synchronous build call.
static var _faction_filter: int = -1

static func set_faction_filter(faction: int) -> void:
	_faction_filter = faction


static func get_faction_filter() -> int:
	return _faction_filter


# Restrict a pool to the active faction. STRICT — returns the filtered set even when
# empty (the WaveGen pickers degrade to the faction's COMMON universals, which are
# always unlocked, and the heavy/elite pickers handle empty gracefully). An earlier
# "fall back to the UNFILTERED pool" leaked other factions' exclusives whenever a
# faction's tier-pool was empty at a depth (gunship showing in every faction at sd=1)
# — DO NOT reintroduce it.
static func _faction_filtered(pool: Array) -> Array:
	if _faction_filter < 0:
		return pool
	return pool.filter(func(e): return Factions.allowed_in(str(e.get("scene", "")), _faction_filter))

# Legacy shoot-pattern producers (SingleShot/AimedShot/BurstShot/SpreadShot) retired from
# this file by Weapons 3b (2026-06-13) — make_shoot now builds the unified Weapon. The
# classes themselves still exist (embedded in designer .tres + a few enemy scenes).
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

# Bullet variant resources — wired per entry below.
const BV_Basic        = preload("res://data/bullets/basic.tres")
const BV_SpreadPellet = preload("res://data/bullets/spread_pellet.tres")
const BV_AimedSniper  = preload("res://data/bullets/aimed_sniper.tres")
const BV_BurstRound   = preload("res://data/bullets/burst_round.tres")
const BV_PlasmaOrb    = preload("res://data/bullets/plasma_orb.tres")
const BV_HeavySlug    = preload("res://data/bullets/heavy_slug.tres")
const BV_DropPellet   = preload("res://data/bullets/drop_pellet.tres")
# Zealot faction projectiles (Roman 2026-06-16) — assignable in the Enemy Bench.
const BV_ZealotBall   = preload("res://data/bullets/zealot_ball.tres")
const BV_ZealotBolt   = preload("res://data/bullets/zealot_bolt.tres")
const BV_ZealotLaser  = preload("res://data/bullets/zealot_laser.tres")
const BV_ZealotWave   = preload("res://data/bullets/zealot_wave.tres")

# Shared firing mounts (M6 mount migration 2026-06-16). The privateer gunship's two weapons —
# previously hardcoded in enemy_gunship.gd — as data: an alternating-muzzle MG burst (Muzzle*) and
# dual wingtip cannons (Cannon*). Reused across every gunship roster entry (firing is identical).
const GUNSHIP_MOUNTS := [
	{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet,
	  "aim": "at_player", "count": 3, "burst_interval": 0.1, "fire_min": 2.0, "fire_max": 2.0 },
	{ "kind": "gun", "marker": "Cannon*", "marker_mode": "all", "payload": BV_HeavySlug,
	  "aim": "straight_down", "count": 1, "fire_min": 2.4, "fire_max": 2.4 },
]

# Helix (firecore cruiser) gun turret on its Turret marker — was zealot_turret.mount_all in the
# enemy's _ready (deleted 2026-06-16). The zealot tank-turret strip + heavy slug, 1:1 with _build.
const HELIX_MOUNTS := [
	{ "kind": "turret", "marker": "Turret*", "payload": BV_HeavySlug,
	  "rotation_speed": 3.6, "fire_min": 1.0, "fire_max": 1.6, "aim_tolerance_deg": 14.0,
	  "recoil_frames": 3, "turret_texture": "res://graphics/enemies/zealot-tank-turret.png", "turret_hframes": 3 },
]

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
		# Shiv (charger) — zealot Dart-equivalent: slow telegraphed entry, then accelerates
		# hard in the firing zone and rushes the exit (lane_charge). CHARGE movers come in
		# small groups (Roman 2026-06-08): base_count 6 + no_scale, cap 6. Baked firecore.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_charge",
		"shoot": null,
		"base_count": 6,
		"no_scale": true,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.7, "chaff": true,
	},
	{
		# Shiv (straight) — the same hull as plain fast-down chaff (Roman 2026-06-08:
		# "shivs can also fast down, straight down"). Full-count diver, no charge cap.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_dart.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		# Dart — the canonical first-encounter chaff. Always available.
		# wall: fast chaff arrives as a chunked, gap-shifting wall (not a trickle) so
		# a big dart wave keeps end-of-node momentum (construction §8).
		"unlock_sector": 0, "unlock_depth": 0, "weight": 1.4, "chaff": true, "wall": true,
	},
	# Bomb Drone PULLED 2026-06-14 (Roman — to be reworked). Roster entry removed so it
	# can't spawn; its factions.gd ENEMY_TAGS tag is removed too. Scene/script/codex/
	# pattern-eligibility kept intact for the rework — re-add this dict to restore it.
	{
		# Manta (M6c, Roman art 2026-06-07) — REPLACES the Drifter. Same role/slot
		# (basic drifting chaff shooter) on the new zealot two-frame sprite, but
		# fires from a single CENTRAL muzzle (straight) rather than the diagonal
		# popper. Stays a zealot UNIVERSAL (enemy_drifter.tscn retired from tags).
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_drift",
		"shoot": "single",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 4,
		# Fire-rate pass (2026-05-30, Roman): was ~2.4-3.2s (slowest shooter).
		# Tightened to ~1.6-2.2s (~33% faster). Drifter stays a touch slower
		# than firecore so the two chaff types still feel distinct. First-pass.
		"fire_min": 1.6, "fire_max": 2.2,
		"hp_override": 1, "bounty_override": 8,
		# Drifter — basic chaff (slow drifting shooter). Always available so the
		# sector-1/depth-0 opener has a couple of distinct basic types.
		"unlock_sector": 0, "unlock_depth": 0, "weight": 1.2, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},

	# --- Zealot core units (M6c, Roman art 2026-06-07) --------------------
	# Zealot-exclusive enemy_core ships carrying a decorative firecore (glowing
	# center) and a baked DropFirecore component (ALWAYS drop a firecore on death,
	# count 1 — the faction overlay may add a chance of a second). "Acolyte" (was
	# Retro) is the hover/skirmisher gunner; "Drifter" (was Run) is the unarmed
	# runner — both renamed in place by the 2026-06-16 art rework (same UID). Each
	# appears under a few movements for variety.
	{
		# Run (straight) — unarmed firecore-runner; basic descent.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 6,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
	},
	{
		# Run (weave) — unarmed firecore-runner; lane weave.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_weave",
		"shoot": null,
		"base_count": 5,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 6,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.9, "chaff": true,
	},
	{
		# Retro (hover) — firecore hover-gunner, aimed fire from a central muzzle.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "loiter_mid",
		"shoot": "aimed",
		"bullet_variant": BV_Basic,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 2, "bounty_override": 14,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		# Retro (skirmish) — firecore skirmisher, advance/retreat aimed fire.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "advance_retreat",
		"shoot": "aimed",
		"bullet_variant": BV_Basic,
		"base_count": 3,
		"fire_min": 0.9, "fire_max": 1.3,
		"hp_override": 2, "bounty_override": 14,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		# Retro (drift) — firecore drifting gunner.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "lane_drift",
		"shoot": "aimed",
		"bullet_variant": BV_Basic,
		"base_count": 3,
		"fire_min": 1.4, "fire_max": 2.0,
		"hp_override": 2, "bounty_override": 14,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	# Sword (M6c, Roman art 2026-06-07) — zealot medium-speed LANE PUSHER. A long,
	# narrow hull with multiple cycling muzzles (frigate-style) + a rear firecore.
	# Fires shots as it goes: the advance variant pops at fixed band positions
	# (path-phase, since it's a monotonic descent); the cross variant rakes the lane
	# on the timer while traversing. Zealot-exclusive enemy_core.
	{
		# Sword (advance) — SLOW lane pusher with a bespoke rolling broadside
		# (enemy_sword.gd cycles the body muzzles firing down). shoot null = the script
		# fires. recycle 0 = exit at bottom.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "slow_advance",
		"shoot": null,
		"base_count": 3,
		"recycle": 0,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},
	{
		# Sword (cross) — crosses horizontally; the rolling broadside (firing down) reads
		# as a perpendicular curtain raking the lanes it passes. Bespoke firing.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "side_traverse",
		"shoot": null,
		"base_count": 2,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.7, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},
	# (Strafer retired 2026-06-09 — its StrafeRun pass is superseded by the Hotrod below; the
	# enemy_strafer scene/script + the strafe_run pattern were removed.)
	# Hotrod (M6c, Roman art 2026-06-07) — REPLACES the Strafer. Supremacy fast
	# fighter (enemy_core) firing ALTERNATING tracers from its two muzzles (single
	# shot cycles L/R). Dive / straight / weave variants. enemy_strafer.tscn retired
	# from the tag table. Was corporate + bespoke 3-phase; now supremacy + pattern.
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "side_dive",
		"shoot": "single",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 4,
		"recycle": 0,   # high-count chaff shouldn't recycle (Roman 2026-06-08)
		"hp_override": 2, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.9, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": "single",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 4,
		"recycle": 0,
		"hp_override": 2, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_weave",
		"shoot": "single",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 3,
		"recycle": 0,
		"hp_override": 2, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "wide_dodge"],
	},
	# Rush (M6c, supremacy) — fast aggressive fighter firing 3-shot bursts of small
	# bullets from two muzzles (±8). Dive / weave / charge (beeline) variants.
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "side_dive",
		"shoot": "burst",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 3,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "lane_weave",
		"shoot": "burst",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 3,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "wide_dodge"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "beeline",   # charge straight at the player
		"shoot": "burst",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 2,
		"no_scale": true,   # beeline/charge waves stay small (Roman 2026-06-08: cap 1-6)
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.6, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	# Plasma (M6c, supremacy) — NEW medium plasma gunner (the beam shooters stay).
	# Fires aimed wobbling plasma orbs from two muzzles; hold / weave / slide variants.
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter_mid",
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "lane_weave",
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "side_traverse",   # slide across
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.6, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "beeline",
		"shoot": null,
		"base_count": 4,
		"no_scale": true,   # beeline kamikaze waves stay small (Roman 2026-06-08: cap 1-6)
		# Hunter Drones are kamikaze threats, not bounty piñatas — pay
		# mine-equivalent value (1) so killing one doesn't reward more
		# than dodging an asteroid/mine of the same threat profile.
		"bounty_override": 1,
		# Hunter Drone — kamikaze threat; deeper-common. Appears from sector 2,
		# a node or two in. (Was D4 — unreachable on short sectors; pulled to D1.)
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.6, "chaff": true,
	},

	# --- Privateer chaff (M6c, Roman art 2026-06-07) ----------------------
	# Privateer-exclusive (universal=false in factions.ENEMY_TAGS) — these only
	# roll in privateer levels, fleshing out the faction's own set. All three use
	# enemy_core directly (movement + shoot driven by the roster slots; no bespoke
	# scripts). Two-frame sprite: frame 0 hull + frame 1 emissive glow (GlowMask).
	{
		# Green (weave) — privateer chaff. lane_weave wobble. Weight dropped 1.1->0.7 so
		# green waves aren't "heavy on curves" (Roman 2026-06-08) — the drift + straight
		# variants below add variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_weave",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.7, "chaff": true, "wall": true,
	},
	{
		# Green (drift) — slow lane-to-lane slide variant for wave variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "lane_drift",
		"shoot": null,
		"base_count": 5,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.6, "chaff": true,
	},
	{
		# Green (straight) — plain fast diver variant for wave variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.6, "chaff": true, "wall": true,
	},
	{
		# Gray — privateer straight-diver chaff (no weapon). The faction's plain
		# fast descender; pairs with Green as the basic privateer opener fodder.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
	},
	{
		# Drop — privateer caltrop-layer. Descends steadily and DROPS a trail of
		# slow drop_pellets behind itself (rear muzzles at ±6). Firing is path-phase
		# (5 fixed band positions baked on the scene, NOT the timer) so the trail
		# lands at even screen heights regardless of fire_interval. The pellets crawl
		# down at 45 px/s — far slower than the 180 px/s descent — so they hang in
		# the lane behind the dropper as a lingering hazard.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "firecore_straight",
		# Burst-once then exit (Roman 2026-06-08): a single 4-shot burst at one band
		# position (scene fire_path_phases = [0.4]), recycle 0 = leave, don't loop.
		# TODO(M6c r2): +2 shots per depth increment (director-driven burst_count).
		"shoot": "burst", "burst_count": 4,
		"bullet_variant": BV_DropPellet,
		"base_count": 4,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},

	# --- Corporate chaff (M6c, Roman art 2026-06-07) ----------------------
	# Corporate-exclusive (universal=false) mirror of the privateer chaff pack —
	# enemy_core, no bespoke scripts, two-frame hull+glow sprites. Gives corp its
	# own basic fodder alongside the universal Hold gunner.
	{
		# Corp Gray — straight-diver chaff (no weapon). Corp's plain fast descender.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
	},
	{
		# Corp Dart (M6c, Roman 2026-06-07) — corporate version of the Dart: same fast
		# diver role, new corp art, NO shield (faction_shield_exempt on the scene keeps
		# the corporate overlay from shielding it). Replaces curve as corp's basic diver.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_dart.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "fast_straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.2, "chaff": true, "wall": true,
	},
	{
		# Corp Drop — burst-once dropper (Roman 2026-06-08): one 4-shot burst at band
		# 0.4 then exit (recycle 0). TODO(M6c r2): +2 shots per depth increment.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "firecore_straight",
		"shoot": "burst", "burst_count": 4,
		"bullet_variant": BV_DropPellet,
		"base_count": 4,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},

	# --- UNCOMMON ---------------------------------------------------------
	{
		# Burner — beam pair (Roman, 2026-05-31). Bespoke self-driving enemy:
		# arrives in pairs, strings a damaging beam between the two members and
		# descends together; killing either blows up both. Handles its own
		# movement + beam (no Resource slots) so movement/shoot are null, like
		# enemy_firecore_cruiser. Burner waves MUST use formation TOP_TANDEM_PAIRS
		# (index 5) and an EVEN count so every member gets a partner; an odd
		# member simply descends and leaves (no beam) rather than crashing. The
		# generator honors `force_formation` to guarantee this whenever the
		# Burner rolls (single OR mixed wave) — see wave_generator._make_wave_spec
		# and the mixed-wave re-apply in _build_combat_waves. (Roman, 2026-05-31:
		# rolls as a normal UNCOMMON now, wired into production waves.)
		"scene": "res://scenes/enemies/factions/zealot/enemy_burner.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": null,   # handles own movement
		"shoot": null,      # handles own beam
		"base_count": 2,
		"hp_override": 12, "bounty_override": 30,
		# DEPTH GATING (Roman 2026-05-31): now live — _pick_entry honors
		# unlock_sector/unlock_depth via Roster.entries_eligible. Burner is an
		# advanced beam-pair behavior, so it's gated to sector 2 (not a sector-1
		# surprise). Within sector 2+ it can appear from the first node.
		"weight": 0.7, "unlock_sector": 2, "unlock_depth": 0,
		# Guarantee the pair formation + even count every time this rolls.
		# 5 == WaveSpec.Formation.TOP_TANDEM_PAIRS (wave_def.gd). Literal because
		# the roster doesn't preload WaveSpec; the generator validates against the
		# enum.
		"force_formation": 5,
		"force_even_count": true,
	},
	{
		# Corp Weaver — was the universal-core enemy_weaver, now UNIFIED onto the corp
		# enemy_c_s_curve sprite (Roman 2026-06-07): corporate-exclusive lane-weave
		# aimed-plasma gunner. The old no-shoot c_s_curve chaff entry is retired into this
		# (curve now carries muzzles). enemy_weaver.tscn retired from the tag table.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "lane_weave",
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		# M6a.2: restore the plasma-orb wobble via the FIRING LAYER (not the bullet
		# .tres). Matches the boss plasma signature (amp 8 / freq 3).
		"base_count": 2,
		"fire_min": 1.4, "fire_max": 2.2,
		"hp_override": 2, "bounty_override": 10,
		# Weaver — entry-level uncommon (s-curve + aimed). The gentlest uncommon,
		# so it's the first to appear: sector 1, one node in. (Was D4.)
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.9, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "wide_dodge"],
	},
	{
		# Hold (M6c, Roman art 2026-06-07) — REPLACES the corp Hover. Same role
		# (loitering gunner that demands focus, fires on the "hold" phase) on the
		# new two-frame corp sprite (hull + glow). Stays a corporate UNIVERSAL so
		# every faction keeps a loiter-gunner; the old enemy_hover.tscn is retired.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "loiter",
		"shoot": "single",
		"bullet_variant": BV_Basic,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 2, "weight": 0.9, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	# Push (M6c, Roman art 2026-06-07) — REPLACES the Frigate. Supremacy lane pusher
	# (enemy_push.gd, enemy_core) with TWO player-tracking dome turrets firing cannon
	# slugs (aimed, no lead; fast traverse punishes sitting still). Movement from the
	# roster slot: slow descent / mid descent / slow horizontal cross. Stays the
	# tough mid-mission presence anchor. enemy_frigate.tscn retired from the tags.
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn",
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "slow_advance",   # slow straight descent
		"shoot": null,                # bespoke twin turrets
		"hp_override": 28,
		"base_count": 2,
		"recycle": 0,                 # larger lane anchor — exit at bottom, don't loop (Roman 2026-06-08)
		"unlock_sector": 1, "unlock_depth": 1,
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn",
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "firecore_straight",   # mid-speed straight descent
		"shoot": null,
		"hp_override": 28,
		"base_count": 2,
		"recycle": 0,                       # anchor — exit at bottom, don't loop (Roman 2026-06-08)
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.8,
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn",
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "side_traverse",   # slow horizontal cross, lobbing shots
		"shoot": null,
		"hp_override": 28,
		"base_count": 2,
		"recycle": 0,                   # anchor — exit, don't loop (Roman 2026-06-08)
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.7,
	},
	# TODO: Replace cutter with a new horizontal strafe enemy that crosses the screen cleanly
	#{
	#	"scene": "res://scenes/enemies/core/enemy_cutter.tscn",
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
		# Hold (skirmish) — the Skirmisher's behavior UNIFIED onto the corp hold scene
		# (Roman 2026-06-07: hold has the complete/correct markers now). Aggressive
		# aimed-fire advance/retreat, double-muzzle (the muzzle resolver cycles hold's
		# MuzzleL/R). The hold (loiter) entry above is kept too. enemy_skirmisher retired.
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "advance_retreat",
		"shoot": "aimed",
		"bullet_variant": BV_AimedSniper,
		# Experienced gunner: leads the player's velocity a touch (0.15) so sitting
		# still under its aimed-sniper fire is punished, without raising bullet speed.
		"lead_factor": 0.15,
		"base_count": 3,
		"fire_min": 0.7, "fire_max": 1.1,
		"hp_override": 2, "bounty_override": 15,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},

	# --- Privateer medium gunners (M6c, Roman art 2026-06-07) -------------
	# Privateer-exclusive holding-platform gunners. enemy_core + roster slots,
	# no bespoke scripts. Both hold a band and fire on the ShootTimer (loiter is
	# not path-phase, so fire_min/max drive the cadence).
	{
		# Cannon — artillery platform. Holds the mid band and lobs slow, heavy
		# cannon shells (heavy_slug: 60 px/s, 2 dmg) straight down from alternating
		# muzzles (cannon_left/right at ±6). Slow, telegraphed, punishing if ignored.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter_mid",
		"shoot": "single",
		"bullet_variant": BV_HeavySlug,
		"base_count": 2,
		"fire_min": 1.4, "fire_max": 2.0,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 1, "unlock_depth": 2, "weight": 0.8, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	{
		# Pulse — plasma gunner. Holds a deep band and fires AIMED plasma orbs
		# (wobble 8/3, the plasma signature) from two muzzles (±8). Aimed + wobble
		# makes it the privateer pressure unit that demands active dodging.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter_high",
		"shoot": "aimed",
		"bullet_variant": BV_PlasmaOrb,
		"base_count": 2,
		"fire_min": 1.6, "fire_max": 2.4,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},

	# Beamer (aim-DOWN sweeper): descends, then sweeps L↔R firing a straight-down
	# beam that rakes across the band. Bespoke (enemy_beam_shooter.gd) self-drives
	# + self-beams, so movement/shoot are null.
	{
		"scene": "res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn",
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": null,
		"shoot": null,  # uses built-in beam, not shoot_pattern
		"base_count": 2,
		# Beam pressure is a deeper-sector escalation, not a sector-1 opener.
		"unlock_sector": 2, "unlock_depth": 0,
		"conflict_tags": ["beamshooter"],
	},
	# Beamer (aim-at-PLAYER sweeper): same chassis, but each windup locks the
	# beam onto the player's position — it sweeps AND aims. Inherited scene that
	# flips the aim_at_player export. Slightly deeper gate than the aim-down one.
	{
		"scene": "res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn",
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": null,
		"shoot": null,
		"base_count": 2,
		"unlock_sector": 2, "unlock_depth": 2, "weight": 0.7,
		"conflict_tags": ["beamshooter"],
	},
	# Omni Gunship (M6c divergence rework, Roman 2026-06-07): roams with vector
	# thrust (omni), harassing with hull-muzzle tracer bursts + wingtip cannon
	# slugs. Bespoke firing (enemy_gunship.gd, now enemy_core); movement is the
	# omni pattern, so it's a self-roaming presence — formation roles are gone.
	# Single / duo entries give 1 or 2 roamers; no trio (omni roamers don't form up).
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "omni",
		"shoot": null,   # bespoke tracer + cannon firing
		"base_count": 1,
		"no_scale": true,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.8,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "omni",
		"shoot": null,
		"base_count": 2,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 2, "weight": 0.9,
	},
	# Gunship movement variants (Roman 2026-06-07): the same omni-Gunship scene
	# wired to OTHER movements so the generator + conductor have more ways to field
	# it — a medium tracer/cannon gunner that can hold, shift lanes, weave, or
	# skirmish. Firing is identical (enemy_gunship.gd is movement-agnostic); only
	# the movement slot differs. chaff:true + no heavy_class so these roll as regular
	# mid-tier picks (and the lane variants feed the conductor's lane choreography),
	# distinct from the no_scale anchor omni entries above. Modest weights — variety,
	# not a flood.
	{
		# Gunship (hold) — descends and holds the mid band like a loiter gunner.
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "loiter_mid",
		"shoot": null,
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.5, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	{
		# Gunship (weave) — lane-confined weave; a heavier weaver in a lane wave.
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "lane_weave",
		"shoot": null,
		"base_count": 3,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.5, "chaff": true,
	},
	{
		# Gunship (shift) — one-way commit to an adjacent lane, then holds it.
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "lane_shift",
		"shoot": null,
		"base_count": 3,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.5, "chaff": true,
	},
	{
		# Gunship (skirmish) — aggressive advance/retreat, raking on the hold.
		"scene": "res://scenes/enemies/factions/privateer/enemy_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "advance_retreat",
		"shoot": null,
		"base_count": 2,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	# Rocket Gunship (M6c, Roman 2026-06-07): the divergent dupe. SLOW drift hull
	# (movement from the roster slot) that lobs rocket salvos from its launch rack
	# + rakes tracers from its hull muzzles. Bespoke firing (enemy_rocket.gd,
	# enemy_core). A deliberate presence anchor, contrast to the omni Gunship.
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_rocket.tscn",
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "lane_drift",
		"shoot": null,   # bespoke rocket + tracer firing
		"hp_override": 14,
		"base_count": 1,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.7,
	},
	# Bomber wing — large, tough rear-gunners that descend slowly and hold,
	# raking the chasing player with tail turrets. Bespoke (enemy_bomber.gd):
	# self-drives + self-fires, so movement/shoot are null. no_scale locks the
	# wing to a readable formation. Two entries give a wing of 2 OR 3 (each
	# half-weighted so bombers don't appear twice as often as other UNCOMMONs).
	# Extra bounty for the bullet-sponge HP. Gated to sector 2 as a heavier
	# escalation threat.
	{
		"scene": "res://scenes/enemies/core/enemy_bomber.tscn",
		"heavy_class": "anchor",  # 32px-wide (tall) — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": null,
		"shoot": null,
		"hp_override": 30,
		"bounty_override": 120,
		"base_count": 2,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.35,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_bomber.tscn",
		"heavy_class": "anchor",  # 32px-wide (tall) — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": null,
		"shoot": null,
		"hp_override": 30,
		"bounty_override": 120,
		"base_count": 3,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.35,
	},

	# --- RARE -------------------------------------------------------------
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_sapper.tscn",
		"tier": Tier.RARE,
		"size": "small", "tags": [],
		"movement": "omni",
		"shoot": null,
		"base_count": 1,
		# RARE gating (Roman 2026-05-31): rares already only roll when _roll_tier
		# lands RARE (deep nodes / late sectors), so these unlocks are a second,
		# explicit gate on top. "Lighter" rares (sapper, crystal, minelayer,
		# interceptor) open from sector 1's deep nodes; heavier elites wait for
		# sector 2+. (All RARE entries previously had NO unlock fields, which
		# under the new default-0 rule would have made them sector-1/depth-0
		# eligible whenever a RARE tier-roll occurred.)
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_crystal.tscn",
		"tier": Tier.RARE,
		"size": "medium", "tags": [],
		# High hold (Roman 2026-06-07: crystal was coming too far down) — hovers in the
		# upper band instead of the deep "loiter" hold.
		"movement": "loiter_high",
		"shoot": "spread5",
		"bullet_variant": BV_SpreadPellet,
		"base_count": 2,
		"fire_min": 1.8, "fire_max": 2.6,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_minelayer.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "side_traverse",
		"shoot": null,
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_interceptor.tscn",
		# NOT heavy-beat tagged (Roman 2026-06-04): top_dive is a transient
		# dive-through, not a presence-holding anchor. Stays a normal RARE dive squad
		# (reaction-test / direct-challenge). Heavy beats want descend-and-hold types.
		"tier": Tier.RARE,
		"size": "medium", "tags": ["tough"],
		"movement": "side_dive",
		"shoot": null,
		"base_count": 3,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_bulwark.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "bulwark_drift",
		"shoot": null,
		"base_count": 1,
		# Heavy elite — sector 2+.
		"unlock_sector": 2, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_cruiser.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "loiter",
		"shoot": null,
		"base_count": 1,
		"unlock_sector": 2, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "loiter",
		"shoot": null,
		"base_count": 1,
		# Drone carrier — top-tier elite, latest of the standard rares.
		"unlock_sector": 3, "unlock_depth": 0,
	},
	# Firecore Cruiser "Helix" (M6c rework, Roman 2026-06-07): a slow zealot capital
	# with a player-tracking hook-turret BEAM + two glowing cores, dropping firecores
	# on death. Now enemy_core: movement comes from the roster slot (clamped to ~1px/f
	# in the script), giving it several ways to arrive — cross (side_traverse), hold
	# (loiter), drift (lane_drift). shift/advance can be added later. Bespoke beam +
	# baked DropFirecore (count 2). RARE capital, kept scarce by the tier-roll.
	{
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn",
		"mounts": HELIX_MOUNTS,
		"heavy_class": "capital",
		"tier": Tier.RARE,
		"size": "huge", "tags": ["tough"],
		"movement": "side_traverse",  # cross the screen
		"shoot": null,                # bespoke beam turret
		"base_count": 1,
		"no_scale": true,
		"hp_override": 32, "bounty_override": 100,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.6,
	},
	{
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn",
		"mounts": HELIX_MOUNTS,
		"heavy_class": "capital",
		"tier": Tier.RARE,
		"size": "huge", "tags": ["tough"],
		"movement": "loiter",  # descend + hold
		"shoot": null,
		"base_count": 1,
		"no_scale": true,
		"hp_override": 32, "bounty_override": 100,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
	},
	{
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn",
		"mounts": HELIX_MOUNTS,
		"heavy_class": "capital",
		"tier": Tier.RARE,
		"size": "huge", "tags": ["tough"],
		"movement": "lane_drift",  # slow lane drift
		"shoot": null,
		"base_count": 1,
		"no_scale": true,
		"hp_override": 32, "bounty_override": 100,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
	},
	{
		# Firecore Drone (Roman, 2026-05-31). Small + tough; descends slowly
		# wreathed in 1-4 concentric rings of orbiting bullet visuals. Doesn't
		# shoot — killing it DETACHES the rings into real enemy_bullets that fly
		# outward as expanding waves. Bespoke self-driving enemy (handles its own
		# descent + ring orbit + death release), so movement/shoot are null like
		# burner/firecore_cruiser. Rolls as a normal UNCOMMON (Roman, 2026-05-31)
		# — self-manages its rings so default formation/count is fine (no even-count
		# requirement). Keep hp_override in sync with the script's max_health (10)
		# so the codex matches.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_bloom.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": null,   # handles own movement
		"shoot": null,      # handles own ring release
		"base_count": 3,
		"hp_override": 10, "bounty_override": 25,
		# DEPTH GATING (Roman 2026-05-31): NEW advanced enemy — the death-burst
		# ring release is a learned threat, so gate it out of sector 1 entirely.
		# Unlocks sector 2 (peer of Burner). Had no unlock fields, which under
		# the new default-0 rule would have put it at sector-1/depth-0.
		"unlock_sector": 2, "unlock_depth": 0,
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


# Depth-gated tier pool (Roman 2026-05-31, enemy unlock gating).
# Returns the entries of `tier` whose unlock thresholds are met for the given
# progression coordinate, where:
#   sector_idx   <- WaveGen.build's sector_depth   (1-based: sector 1, 2, 3...)
#   sector_depth <- WaveGen.build's level_index    (0-based: 0 = first combat
#                   node since the sector reset)
# An entry is eligible when BOTH:
#   sector_idx   >= unlock_sector   (absent/0 => always; treated as 0)
#   sector_depth >= unlock_depth    (absent/0 => always; treated as 0)
# IMPORTANT: default is 0 (always-available), NOT 1. The first combat node
# passes level_index = 0, so any unlock_depth >= 1 enemy is gated out of the
# sector opener — exactly the "fresh sector opens calm" intent. The basic
# chaff carry unlock_depth 0 explicitly so the filtered pool is non-empty at
# (sector 1, depth 0) BY CONSTRUCTION, without relying on a fallback.
# Callers (WaveGen._pick_entry) still apply their own last-ditch fallback.
static func entries_eligible(tier: int, sector_idx: int, sector_depth: int) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if int(e["tier"]) != tier:
			continue
		if int(e.get("unlock_sector", 0)) > sector_idx:
			continue
		if int(e.get("unlock_depth", 0)) > sector_depth:
			continue
		out.append(e)
	return _faction_filtered(out)


# INVARIANT (Roman 2026-06-04): heavy beats want PRESENCE — types that descend the
# screen and hold (loiter-gunners, broadside warships, slow descenders). Transient
# dive-throughs (interceptor/top_dive) are deliberately NOT heavy_class-tagged; they
# stay normal RARE rolls. So every anchor/capital entry should read as a presence
# anchor, not a fly-by.
#
# Depth-gated HEAVY pool (M5, heavy-beat structure). Returns entries tagged with
# `heavy_class` (== "anchor" for 32px-wide silhouettes, "capital" for 64px-wide)
# that are unlocked at the given progression coordinate. The wave generator's
# midpoint anchor pulls "anchor"; the closing coda prefers "capital" (falls back to
# "anchor" when no capital is unlocked yet — e.g. all of sector 1). Spans tiers on
# purpose: heavies live across UNCOMMON (frigate/gunship/bomber/beamers) and RARE
# (interceptor/cruiser/bulwark/drone_carrier/firecore_cruiser). Same unlock rules as
# entries_eligible (absent threshold => 0 => always-available).
#   sector_idx   <- WaveGen.build's sector_depth (1-based)
#   sector_depth <- WaveGen.build's level_index  (0-based combat node)
static func heavies_eligible(heavy_class: String, sector_idx: int, sector_depth: int) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if String(e.get("heavy_class", "")) != heavy_class:
			continue
		if int(e.get("unlock_sector", 0)) > sector_idx:
			continue
		if int(e.get("unlock_depth", 0)) > sector_depth:
			continue
		out.append(e)
	return _faction_filtered(out)


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
	# Resolve the movement KEY via the eligibility matrix: the entry's own movement (identity)
	# unless it opts into variety ("vary": true) — then a flat-random eligible key. Behavior-
	# preserving until eligibility is expanded + an entry opts in (pattern_eligibility.gd).
	var key: String = PatternEligibility.resolve(entry)
	match key:
		# --- STRAIGHT family (named by speed; rungs of 60 px/s = 1 px/f), Roman 2026-06-08 ---
		"straight_crawl":
			return _straight(60.0)    # 1 px/f (was slow_advance)
		"straight_slow":
			return _straight(120.0)   # 2 px/f
		"straight_medium":
			return _straight(180.0)   # 3 px/f (was firecore_straight / generic straight)
		"straight_fast":
			return _straight(300.0)   # 5 px/f (was fast_straight)
		"straight_reflex":
			return _straight(360.0)   # 6 px/f (reflex rung)
		"straight_charge":
			# Slow telegraphed entry, then accelerate hard in the fire zone (was lane_charge).
			return LaneCharge.new()
		# --- SKIRMISH loops (replaces the broken advance_retreat) ---
		"skirmish_loop":
			return _skirmish(Skirmish.Shape.LOOP)
		"skirmish_figure8":
			return _skirmish(Skirmish.Shape.FIGURE8)
		# --- DRIFT (tank hold + jiggle; heights match loiter), was bulwark_drift ---
		"drift_low":
			return _drift(130.0)
		"drift_mid":
			return _drift(90.0)
		"drift_high":
			return _drift(50.0)
		"lane_weave":
			# Weaver (m6 §13, lane_path engine) — wobble WITHIN its own lane while
			# descending. Lane-confined: ~10px swing < half lane width (12), never
			# crosses into a neighbor. (P2: lane_path is the production lateral engine.)
			var m = LanePath.new()
			m.shape = LanePath.Shape.WEAVE
			m.down_speed = 120.0
			m.weave_lanes = 0.32
			m.weave_frequency = 0.9
			m.mirrored = randf() < 0.5
			return m
		"lane_drift":
			# Drifter (m6 §13) — a single SLOW lane-to-lane slide timed to the fire
			# zone (Roman 2026-06-06): holds the spawn lane through entry, starts
			# sliding as it crosses into the fire zone, and is fully in the adjacent
			# lane by the band bottom. Lane-aware (commits only if the target is free).
			var m = LanePath.new()
			m.shape = LanePath.Shape.HOOK
			m.zone_timed = true
			m.shift_lanes = 1
			m.down_speed = 110.0
			m.mirrored = randf() < 0.5
			return m
		"lane_shift":
			# Shifter (m6 §13) — descend, then a one-way COMMIT to an adjacent lane
			# (only if free), then hold the destination. The HOOK = Shifter decision.
			# Live as of 2026-06-07: the Gunship (shift) roster variant uses this.
			var m = LanePath.new()
			m.shape = LanePath.Shape.HOOK
			m.down_speed = 120.0
			m.shift_lanes = 1
			m.shift_delay = 0.6
			m.shift_duration = 0.7
			m.mirrored = randf() < 0.5
			return m
		"lane_hook":
			# Down a lane, curve into the adjacent lane at the fire-zone midpoint, then climb
			# back up and off the TOP. For droppers — drop the volley, then turn and burn.
			var m = LanePath.new()
			m.shape = LanePath.Shape.DIVE_RETURN
			m.down_speed = 140.0
			m.shift_lanes = 1
			m.mirrored = randf() < 0.5
			return m
		"lane_cut":
			# Down a lane, curve LEFT/RIGHT at the fire-zone midpoint, then run horizontally
			# off the side (Roman 2026-06-08).
			var m = LanePath.new()
			m.shape = LanePath.Shape.LANE_CUT
			m.down_speed = 160.0
			m.mirrored = randf() < 0.5
			return m
		"loiter_low", "loiter_mid", "loiter_high":
			# Holder (m6 §13). Hover into the fire band, hold with a gentle
			# bob/sway, then accelerate away. Exit accel/max trimmed (was
			# 600/700) so a player drifting upward isn't rammed by an exit.
			# low/mid/high pick the hold band (deeper = more pressure). Base
			# "loiter" keeps the historical deep hold for back-compat.
			var m = Loiter.new()
			match key:
				"loiter_high": m.hover_y = 50.0
				"loiter_mid": m.hover_y = 90.0
				_: m.hover_y = 130.0   # loiter / loiter_low — deep hold
			m.enter_speed = 180.0
			m.loiter_time = 3.0
			m.exit_accel = 400.0
			m.exit_max_speed = 480.0
			return m
		"side_turn":
			# Advance horizontally in, rounded-turn down into the lane, descend to exit.
			return SideTurn.new()
		"side_dive":
			# Like side_turn but a swift descent (Roman 2026-06-08).
			var m = SideTurn.new()
			m.down_speed = 300.0
			m.advance_time = 0.45
			return m
		"side_traverse":
			# Slow horizontal cross (Minelayer). Base now randomizes its latitude band
			# (Roman 2026-06-11: expanded into high/mid/low). Explicit *_high/_mid/_low
			# keys force a specific band.
			return _side_traverse([50.0, 90.0, 128.0][randi() % 3])
		"side_traverse_high":
			return _side_traverse(50.0)
		"side_traverse_mid":
			return _side_traverse(90.0)
		"side_traverse_low":
			return _side_traverse(128.0)
		"hunt_beeline":
			# Player-tracking pursuit — threatens, shouldn't connect (was beeline).
			var m = BeelinePlayer.new()
			m.max_speed = 190.0
			m.accel = 280.0
			return m
		"hunt_omni":
			# Omni-thrust vector roamer — holds stand-off range + strafes (was omni).
			# Leaves after a few passes instead of harassing forever (Roman 2026-06-11).
			var omt = OmniThrust.new()
			omt.max_passes = 3
			return omt
		"pendulum":
			# Dual-band vertical ping-pong diver w/ aim-fire dwell (ported from crystal).
			return Pendulum.new()
		"proximity_chase":
			# Drift straight until near the player, then activate a chase (smart mine/bomblet).
			return ProximityChase.new()
		"loiter_sweep":
			# Descend to a band, then rake L↔R (beam shooter SWEEP locomotion). Renamed from
			# "beam_sweep" 2026-06-09 — behavior unchanged.
			return LoiterSweep.new()
	# Default: a readable medium straight.
	return _straight(180.0)


# --- make_movement helpers (Roman 2026-06-08 pattern overhaul) ---
static func _straight(speed: float) -> Resource:
	var m = StraightDown.new()
	m.speed = speed
	return m


static func _skirmish(shape: int) -> Resource:
	var m = Skirmish.new()
	m.shape = shape
	return m


static func _drift(hover_y: float) -> Resource:
	var m = Drift.new()
	m.hover_y = hover_y
	return m


static func _side_traverse(travel_y: float) -> Resource:
	var m = SideTraverse.new()
	m.travel_y = travel_y
	m.speed = 75.0
	m.direction = 1 if randf() < 0.5 else -1
	return m


# Build the behavior components for an entry (m6 §3 component framework). Forward-
# compatible: an entry may list pre-built EnemyComponent resources under "components";
# faction overlays + a future key->script table extend this. Returns [] until enemies
# declare components, so the whole pipeline is inert today.
static func make_components(entry: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = entry.get("components", [])
	if listed is Array:
		for c in listed:
			if c != null:
				# Duplicate so wave.components_override owns FRESH instances. The roster entry's
				# component resources are shared module-wide, so a pre-_init mutation (e.g.
				# director._resolve_shields bumping ShieldComponent.capacity) would otherwise
				# accumulate on the roster's shared copy across every spawn. Mirrors
				# Factions.build_components' fresh-per-spawn contract. (Health audit 2026-06-15.)
				out.append(c.duplicate() if c is Resource else c)
	return out


# Build the enemy's firing MOUNTS (extra guns/turrets/launchers/beams beyond the hull shoot_pattern)
# from an entry's optional "mounts" key — a list of plain dicts. Mirrors make_shoot/make_components:
# returns [] when absent (every existing entry → unchanged behavior). Each dict → one MountSpec.
static func make_mounts(entry: Dictionary) -> Array:
	var listed: Variant = entry.get("mounts", [])
	return make_mount_specs(listed) if listed is Array else []


# Shared dict → MountSpec converter, also used by the Enemy Bench. "payload" is a BulletVariant
# resource (or null); "payload_scene"/"turret_texture" may be a res:// string or a loaded resource.
# Specs are FRESH per call (the wave/instance owns them — the shared-resource-mutation rule).
static func make_mount_specs(dicts: Array) -> Array:
	var out: Array = []
	for d in dicts:
		if d is Dictionary:
			out.append(_mount_from_dict(d))
	return out


const _MOUNT_KIND := {"gun": 0, "turret": 1, "launcher": 2, "beam": 3}        # MountSpec.Kind
const _MOUNT_AIM := {"straight_down": 0, "toward_center": 1, "at_player": 2, "forward": 3}  # MountSpec.Aim
const _MOUNT_MODE := {"all": 0, "cycle": 1}                                    # MountSpec.MarkerMode

static func _mount_from_dict(d: Dictionary) -> Resource:
	var m = MountSpec.new()
	m.kind = int(_MOUNT_KIND.get(String(d.get("kind", "gun")), 0))
	m.marker = String(d.get("marker", ""))
	m.marker_mode = int(_MOUNT_MODE.get(String(d.get("marker_mode", "all")), 0))
	m.payload = d.get("payload", null)
	var ps: Variant = d.get("payload_scene", null)
	if ps is String and ps != "":
		m.payload_scene = load(ps)
	elif ps is PackedScene:
		m.payload_scene = ps
	m.fire_interval_min = float(d.get("fire_min", d.get("fire_interval_min", 2.0)))
	m.fire_interval_max = float(d.get("fire_max", d.get("fire_interval_max", m.fire_interval_min)))
	m.aim = int(_MOUNT_AIM.get(String(d.get("aim", "straight_down")), 0))
	m.lead_factor = float(d.get("lead_factor", 0.0))
	m.bullet_speed = float(d.get("bullet_speed", -1.0))
	m.count = int(d.get("count", 1))
	m.spread_deg = float(d.get("spread_deg", 0.0))
	m.burst_interval = float(d.get("burst_interval", 0.0))
	m.homing_rate = float(d.get("homing_rate", 0.0))
	m.wobble_amplitude = float(d.get("wobble_amplitude", 0.0))
	m.wobble_frequency = float(d.get("wobble_frequency", 0.0))
	m.rotation_speed = float(d.get("rotation_speed", 3.6))
	m.arc_deg = float(d.get("arc_deg", 0.0))
	m.rest_angle_deg = float(d.get("rest_angle_deg", 0.0))
	m.arc_gate = bool(d.get("arc_gate", false))
	m.lock_to_fire = bool(d.get("lock_to_fire", false))
	m.lock_duration = float(d.get("lock_duration", 0.4))
	m.aim_tolerance_deg = float(d.get("aim_tolerance_deg", 14.0))
	m.recoil_frames = int(d.get("recoil_frames", 0))
	var tt: Variant = d.get("turret_texture", null)
	if tt is String and tt != "":
		m.turret_texture = load(tt)
	elif tt is Texture2D:
		m.turret_texture = tt
	m.turret_hframes = int(d.get("turret_hframes", 1))
	m.beam_config = d.get("beam_config", {})
	return m


static func make_shoot(entry: Dictionary) -> Resource:
	var kind: Variant = entry.get("shoot", null)
	if kind == null:
		return null
	# Weapons 3b (2026-06-13): every roster shoot key builds the unified Weapon resource
	# — the legacy SingleShot/AimedShot/SpreadShot/BurstShot producers are gone here. The
	# volley SHAPE is fire_pattern; payload + movement axis + per-pattern speed are the
	# shared shoot_pattern knobs, set once below. (Behavior-equivalent: SINGLE/AIMED/BURST
	# are identical to the old classes, SPREAD is the same symmetric fan. nose/broadside
	# were already Weapon.)
	var w = Weapon.new()
	w.bullet_scene = EnemyBullet
	match kind:
		"single", "single_fast":
			w.fire_pattern = Weapon.FirePattern.SINGLE
			w.aim = Weapon.Aim.STRAIGHT_DOWN
		"single_diagonal":
			# Side-spawn chaff angles toward center (left→right-down, right→left-down), ~30°.
			w.fire_pattern = Weapon.FirePattern.SINGLE
			w.aim = Weapon.Aim.TOWARD_CENTER
			w.aim_angle_deg = 30.0
		"aimed":
			# Optional target-leading ("experienced gunner"): 0 = aim at the player's
			# current spot; ~0.15 leads by player.velocity (entry opts in).
			w.fire_pattern = Weapon.FirePattern.AIMED
			w.aim = Weapon.Aim.AT_PLAYER
			w.lead_factor = float(entry.get("lead_factor", 0.0))
		"burst":
			w.fire_pattern = Weapon.FirePattern.BURST
			w.aim = Weapon.Aim.STRAIGHT_DOWN
			w.burst_count = int(entry.get("burst_count", 3))
			w.burst_interval = 0.18
		"spread5":
			w.fire_pattern = Weapon.FirePattern.SPREAD
			w.aim = Weapon.Aim.STRAIGHT_DOWN
			w.spread_count = 5
			w.spread_degrees = 36.0
		"nose":
			# Fire along the nose (Aim.FORWARD). Pair the host with auto_rotate +
			# fire_only_on_target so it strafes the player (the strafer).
			w.fire_pattern = Weapon.FirePattern.SINGLE
			w.aim = Weapon.Aim.FORWARD
		"broadside":
			# Rolling naval broadside out the player-facing flank (salvaged from the frigate).
			# Host needs GunLeft1..N / GunRight1..N markers; set fire_interval to the per-gun
			# beat (~0.34s) so successive ticks ripple down the hull.
			w.fire_pattern = Weapon.FirePattern.BROADSIDE
			w.broadside_guns = int(entry.get("broadside_guns", 5))
		_:
			return null
	# Payload + shared axis/speed knobs (the roster still keys the payload "bullet_variant").
	w.payload = entry.get("bullet_variant", null)
	# Projectile-movement axis (M6a.2): the firing layer drives homing/wobble (e.g. the
	# Weaver's plasma orb wobbles); faction/sector can later multiply them.
	w.homing_rate = entry.get("homing_rate", 0.0)
	w.wobble_amplitude = entry.get("wobble_amplitude", 0.0)
	w.wobble_frequency = entry.get("wobble_frequency", 0.0)
	# Absolute per-pattern bullet speed (rung-authored, px/s). -1 leaves the variant's
	# speed; >0 replaces it before faction/sector scaling.
	w.bullet_speed = float(entry.get("bullet_speed", -1.0))
	return w
