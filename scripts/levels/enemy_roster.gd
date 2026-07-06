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

# Size→locomotion base (locomotion refactor 2026-06-19). The chassis owns kinematics; a movement
# pattern reads these for SCALE (it owns only SHAPE). `base_rung` is the base linear speed in px/s
# on a clarity rung (bigger size = slower); a per-entry `engine` offset shifts ONLY this. `weight`
# is inertia/turn mass (bigger = heavier), `turn_rate` deg/s, `accel` px/s². Behaviour-preserving
# migration sets each enemy's `engine` so its resolved move_speed lands on its OLD speed; these
# bases are the authoring anchors, tuned in the Enemy Bench Locomotion tab. (SIZE_TABLE.speed_mult
# is now dead — removed with the bench rework.)
# base_rung dropped one clarity rung (−60 px/s) 2026-07-02 (Roman: "bring all enemy speeds down a
# rung"). huge/giant stay at 60 (the lowest whole rung — one more rung would hit the 30 creep sub-rung).
const SIZE_LOCOMOTION := {
	"tiny":   {"base_rung": 180.0, "weight": 1.0, "turn_rate": 240.0, "accel": 500.0},
	"small":  {"base_rung": 120.0, "weight": 1.0, "turn_rate": 240.0, "accel": 410.0},
	"medium": {"base_rung":  60.0, "weight": 2.0, "turn_rate": 120.0, "accel": 330.0},
	"large":  {"base_rung":  60.0, "weight": 3.0, "turn_rate":  90.0, "accel": 240.0},
	"huge":   {"base_rung":  60.0, "weight": 4.0, "turn_rate":  45.0, "accel": 180.0},
	"giant":  {"base_rung":  60.0, "weight": 5.0, "turn_rate":  23.0, "accel":  90.0},
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
const AuthoredPathLibrary = preload("res://scripts/enemies/patterns/authored_path_library.gd")
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
# Privateer faction projectiles (2026-06-20) — family-tagged; in a privateer level they ARE the
# fired bullet, and the appearance facet maps them to other factions' clones if the unit travels.
const BV_PrivBall     = preload("res://data/bullets/privateer_ball.tres")
const BV_PrivBolt     = preload("res://data/bullets/privateer_bolt.tres")
const BV_PrivLaser    = preload("res://data/bullets/privateer_laser.tres")
const BV_PrivWave     = preload("res://data/bullets/privateer_wave.tres")

# Shared firing mounts (M6 mount migration 2026-06-16). The privateer gunship's two weapons —
# previously hardcoded in enemy_gunship.gd — as data: an alternating-muzzle MG burst (Muzzle*) and
# dual wingtip cannons (Cannon*). Reused across every gunship roster entry (firing is identical).
const GUNSHIP_MOUNTS := [
	{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "all", "payload": BV_PrivLaser,
	  "aim": "forward", "count": 2, "burst_interval": 0.25, "fire_min": 4.5, "fire_max": 4.5, "no_inertia": true },
	{ "kind": "gun", "marker": "Cannon*", "marker_mode": "all", "payload": BV_PrivLaser,
	  "aim": "forward", "count": 2, "burst_interval": 0.15, "fire_min": 4.5, "fire_max": 4.5, "no_inertia": true },
]

# Helix (firecore cruiser) gun turret on its Turret marker — was zealot_turret.mount_all in the
# enemy's _ready (deleted 2026-06-16). The zealot tank-turret strip + heavy slug, 1:1 with _build.
const HELIX_MOUNTS := [
	{ "kind": "turret", "marker": "Turret*", "payload": BV_HeavySlug,
	  "rotation_speed": 3.6, "fire_min": 1.0, "fire_max": 1.6, "aim_tolerance_deg": 14.0,
	  "recoil_frames": 3, "turret_texture": "res://graphics/enemies/zealot-tank-turret.png", "turret_hframes": 3 },
]

# Beamer beam mounts (ported from enemy_beam_shooter.gd 2026-06-23): the configurable RAY beam as a
# data BEAM mount that begins on settle_y (was the bespoke begin-on-settle). cycle 0=LOOP_IDLE,
# endpoint 0=RAY, aim_mode 0=LOCAL_FORWARD (SWEEP, straight down — the loiter_sweep movement rakes
# it) / 2=TRACKING (CHASE, tracks the player). MountBuilder attaches the BeamEmitter to the marker.
const BEAMER_SWEEP_MOUNT := [{ "kind": "beam", "marker": "BeamEmitter", "beam_config": {
	"idle_time": 0.9, "windup_time": 1.3, "firing_time": 1.1, "cooldown_time": 1.5,
	"cycle": 0, "autostart": false, "settle_y": 58.0, "endpoint": 0, "aim_mode": 0,
	"reach": 320.0, "dps": 3.0, "hit_radius": 8.0, "emitter_offset": Vector2(0, 0), "target_group": "player" } }]
const BEAMER_CHASE_MOUNT := [{ "kind": "beam", "marker": "BeamEmitter", "beam_config": {
	"idle_time": 0.9, "windup_time": 1.3, "firing_time": 1.1, "cooldown_time": 1.5,
	"cycle": 0, "autostart": false, "settle_y": 58.0, "endpoint": 0, "aim_mode": 2, "tracking_rate": 1.3,
	"reach": 320.0, "dps": 3.0, "hit_radius": 8.0, "emitter_offset": Vector2(0, 0), "target_group": "player" } }]

# Crusader (Roman 2026-06-20) — the large zealot capital. FOUR gun turrets on the Helix tank-turret
# chassis (the "Turret*" glob matches TurretL1/R1/L2/R2) firing Zealot Balls, PLUS two forward hull
# muzzles (MuzzleL/R) firing Zealot Lasers. Payloads + cadence from Roman's Enemy Bench (2026-06-20);
# the turret keeps the Helix visual/rotation fields (the bench doesn't expose those). Realized by
# MountBuilder in enemy_base._ready.
const CRUSADER_MOUNTS := [
	{ "kind": "turret", "marker": "Turret*", "payload": BV_ZealotBall,
	  "rotation_speed": 3.6, "fire_min": 1.0, "fire_max": 1.0, "aim_tolerance_deg": 14.0,
	  "recoil_frames": 3, "turret_texture": "res://graphics/enemies/zealot-tank-turret.png", "turret_hframes": 3 },
	{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "all", "payload": BV_ZealotLaser,
	  "aim": "forward", "count": 1, "fire_min": 1.4, "fire_max": 1.4 },
]

# Push's player-tracking dome turrets — one per Turret* marker, aimed heavy slugs, fast traverse.
# Was hand-built in enemy_push.gd (deleted from the scene 2026-06-19); now a data mount on enemy_core.
const PUSH_MOUNTS := [
	{ "kind": "turret", "marker": "Turret*", "payload": BV_HeavySlug, "aim": "straight_down",
	  "rotation_speed": 3.6, "fire_min": 1.0, "fire_max": 1.0, "aim_tolerance_deg": 14.0,
	  "recoil_frames": 3, "turret_texture": "res://graphics/enemies/turret_s_dome.png", "turret_hframes": 3 },
]

# Rocket gunship — two weapons off its marker rack, was hand-timed in enemy_rocket.gd (2026-06-19):
# rocket salvos from the cycled launch rack + aimed tracer bursts from the hull muzzles.
const ROCKET_MOUNTS := [
	{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "all", "payload": BV_Basic,
	  "aim": "forward", "count": 1, "fire_min": 4.0, "fire_max": 4.0, "fire_only_on_target": true, "spread_deg": 0.0 },
	{ "kind": "launcher", "marker": "Launcher*", "marker_mode": "outward",
	  "payload_scene": "res://scenes/projectiles/enemy_rocket.tscn",
	  "aim": "straight_down", "count": 6, "burst_interval": 0.15, "fire_min": 3.0, "fire_max": 3.0, "no_inertia": true, "spread_deg": 0.0 },
]

# Bomber tail gun — retuned via Enemy Bench (2026-07-05): a straight-down cycling gun on the
# TurretTail marker firing a 3-round burst of the default enemy bullet. Shared by the two B-220
# bomber entries (the thin variant carries its own faster inline mount). Realized by MountBuilder
# in enemy_base._ready.
const BOMBER_TAIL_MOUNT := [
	{ "kind": "gun", "marker": "TurretTail", "marker_mode": "cycle", "payload": preload("res://data/bullets/ball.tres"),
	  "aim": "straight_down", "count": 3, "burst_interval": 0.1, "fire_min": 3.0, "fire_max": 3.0, "spread_deg": 0.0 },
]

# Minelayer — drops dumb bomblets while crossing, then scatters a cluster on death. Was bespoke
# (_process timer + explode scatter in minelayer.gd); now a TIMER + DEATH emitter pair (2026-06-19).
const MINELAYER_MOUNTS := [
	{ "kind": "entity", "trigger": "cadence", "payload_scene": "res://scenes/enemies/enemy_bomblet.tscn", "fire_min": 1.0, "fire_max": 1.0, "count": 1, "band_only": true, "max_emits": 3, "no_inertia": true, "bullet_speed": 60.0 },
	{ "kind": "entity", "trigger": "death", "payload_scene": "res://scenes/enemies/enemy_bomblet.tscn", "count": 6, "scatter": 28.0, "no_inertia": true, "bullet_speed": 60.0 },
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
		"movement": "straight_charge",
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
		"movement": "straight_charge",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_core_s_dart.tscn",
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		# Dart — the canonical first-encounter chaff. Always available.
		# wall: fast chaff arrives as a chunked, gap-shifting wall (not a trickle) so
		# a big dart wave keeps end-of-node momentum (construction §8).
		"unlock_sector": 0, "unlock_depth": 0, "weight": 1.4, "chaff": true, "wall": true,
	},
	{
		# Flechette (2026-06-20) — new core chaff, built off the Dart. Unarmed (no Muzzle)
		# wall-filler; carries a Livery layer (auto-tinted per faction). allowed_in
		# [Corp, Priv] via factions.ENEMY_TAGS. Also the Hive's released swarm unit.
		"scene": "res://scenes/enemies/core/enemy_core_s_flechette.tscn",
		"engine": -1,
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"shoot": null,
		"base_count": 8,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0, "chaff": true, "wall": true,
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
		"mounts": [{ "kind": "gun", "marker": "Muzzle", "payload": BV_ZealotBall, "aim": "forward", "fire_min": 1.0, "fire_max": 1.0, "count": 1, "spread_deg": 0.0 }],
		"engine": -3,
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
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
		"movement": "straight",
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
		"movement": "straight",
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
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_Basic, "aim": "at_player", "count": 1, "fire_min": 1.6, "fire_max": 2.4 }],
		"base_count": 2,
		"hp_override": 2, "bounty_override": 14,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		# Retro (skirmish) — firecore skirmisher, advance/retreat aimed fire.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_Basic, "aim": "at_player", "count": 1, "fire_min": 0.9, "fire_max": 1.3 }],
		"base_count": 3,
		"hp_override": 2, "bounty_override": 14,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		# Retro (drift) — firecore drifting gunner.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_Basic, "aim": "at_player", "count": 1, "fire_min": 1.4, "fire_max": 2.0 }],
		"base_count": 3,
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
		# rolling broadside, now a CYCLE mount (see below; was the bespoke enemy_sword.gd).
		# shoot null = no hull gun. recycle 0 = exit at bottom.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn",
		# Rolling broadside as a mount (2026-06-23): CYCLE walks one shot down the Muzzle* rack per beat,
		# straight-down + zone-gated — the bespoke enemy_sword.gd firing, now data. Payload kept as the
		# migration's BV_ZealotBall (was fast_pellet); Roman rectifies the bullet.
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotBall, "aim": "straight_down", "fire_min": 0.18, "fire_max": 0.18, "count": 1, "spread_deg": 0.0, "fire_zone_gated": true }],
		"engine": -1,
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "side_traverse",
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
		# Rolling broadside as a mount (2026-06-23): CYCLE walks one shot down the Muzzle* rack per beat,
		# straight-down + zone-gated — the bespoke enemy_sword.gd firing, now data. Payload kept as the
		# migration's BV_ZealotBall (was fast_pellet); Roman rectifies the bullet.
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotBall, "aim": "straight_down", "fire_min": 0.18, "fire_max": 0.18, "count": 1, "spread_deg": 0.0, "fire_zone_gated": true }],
		"engine": -1,
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
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 1 }],
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
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 1 }],
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
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 1 }],
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
		"engine": -1,   # bench 2026-07-05 (engine_override)
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "hunt_beeline",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 3, "burst_interval": 0.18, "fire_min": 1.5, "fire_max": 1.5 }],
		"base_count": 3,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn",
		"engine": -1,   # bench 2026-07-05 (engine_override)
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "hunt_beeline",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 3, "burst_interval": 0.18, "fire_min": 1.5, "fire_max": 1.5 }],
		"base_count": 3,
		"hp_override": 2, "bounty_override": 12,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "wide_dodge"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn",
		"engine": -1,   # bench 2026-07-05 (engine_override)
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "hunt_beeline",   # charge straight at the player
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 3, "burst_interval": 0.18, "fire_min": 1.5, "fire_max": 1.5 }],
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
		"movement": "loiter", "depth": "high",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": preload("res://data/bullets/wave.tres"), "aim": "at_player", "count": 3, "burst_interval": 0.1, "fire_min": 1.6, "fire_max": 1.6, "no_inertia": true }],
		"base_count": 2,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["aimed_or_spread", "demands_focus"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter", "depth": "high",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": preload("res://data/bullets/wave.tres"), "aim": "at_player", "count": 3, "burst_interval": 0.1, "fire_min": 1.6, "fire_max": 1.6, "no_inertia": true }],
		"base_count": 2,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.7, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter", "depth": "high",   # slide across
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": preload("res://data/bullets/wave.tres"), "aim": "at_player", "count": 3, "burst_interval": 0.1, "fire_min": 1.6, "fire_max": 1.6, "no_inertia": true }],
		"base_count": 2,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.6, "chaff": true,
		"conflict_tags": ["aimed_or_spread"],
	},
	# Hunter Drone (enemy_hunter_drone) RETIRED 2026-06-20 (Roman reorg) — roster entry
	# removed, scene deleted. The Hive now releases Flechettes instead.

	# --- Privateer / core chaff (M6c, Roman art 2026-06-07; reorg 2026-06-20) ----------------------
	# These started privateer-exclusive; the 2026-06-20 reorg promoted Cobra/Caltrop/Jet to
	# CORE (allowed_in [Corp, Priv]) and reworked Green into the core Falchion (universal,
	# allowed_in [Priv] — privateer-only for now). All use enemy_core directly (movement +
	# shoot driven by the roster slots; no bespoke scripts). 3-frame strip: frame 0 hull +
	# frame 1 emissive glow (GlowMask) + frame 2 Livery (auto-tinted per faction at spawn).
	{
		# Falchion (weave) — was the Hornet/Green. lane_weave wobble. Weight dropped 1.1->0.7 so
		# weave waves aren't "heavy on curves" (Roman 2026-06-08) — the drift + straight
		# variants below add variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn",
		"mounts": [{ "kind": "gun", "marker": "Muzzle", "payload": BV_PrivLaser, "aim": "forward", "fire_min": 0.5, "fire_max": 0.5, "count": 1, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.7, "chaff": true, "wall": true,
	},
	{
		# Falchion (drift) — slow lane-to-lane slide variant for wave variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn",
		"mounts": [{ "kind": "gun", "marker": "Muzzle", "payload": BV_PrivLaser, "aim": "forward", "fire_min": 0.5, "fire_max": 0.5, "count": 1, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"shoot": null,
		"base_count": 5,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.6, "chaff": true,
	},
	{
		# Falchion (straight) — plain fast diver variant for wave variety.
		"scene": "res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn",
		"mounts": [{ "kind": "gun", "marker": "Muzzle", "payload": BV_PrivLaser, "aim": "forward", "fire_min": 0.5, "fire_max": 0.5, "count": 1, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"shoot": null,
		"base_count": 6,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 5,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.6, "chaff": true, "wall": true,
	},
	{
		# Cobra — fast diver, now armed (Enemy Bench 2026-06-20): fires an Aimed Sniper round
		# along its nose (forward = down once auto-rotated), a precise poke as it dives.
		"scene": "res://scenes/enemies/core/enemy_core_s_cobra.tscn",
		"engine": -2,   # bench 2026-07-05 (engine_override)
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_AimedSniper, "aim": "forward", "count": 2, "fire_min": 2.0, "fire_max": 2.0, "fire_only_on_target": true }],
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
		"scene": "res://scenes/enemies/core/enemy_core_s_caltrop.tscn",
		"engine": -1,
		"tier": Tier.COMMON,
		"size": "small", "tags": [],
		"movement": "straight",
		# Bench 2026-07-05: rear-firing suspension cannon — a 6-shot forward burst on the timer
		# (was a 4-shot path-phase burst), dropped at rest (no_inertia).
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_DropPellet, "aim": "forward", "count": 6, "burst_interval": 0.1, "fire_min": 3.0, "fire_max": 3.0, "no_inertia": true, "spread_deg": 0.0 }],
		"base_count": 4,
		"recycle": 0,
		"hp_override": 1, "bounty_override": 8,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.8, "chaff": true,
		"conflict_tags": ["dumb_shot"],
	},

	# --- Corporate chaff: collapsed into the core units (2026-06-20) ------
	# The corp Gray/Dart/Drop twins were folded into the now-universal Cobra (enemy_p_s_gray),
	# Dart (enemy_dart) and Caltrop (enemy_p_s_drop), each allowed_in [Corp, Priv]. The corpo
	# copies were cut; corp fields the shared core units (faction sprite/bullets via livery + the
	# projectile-appearance facet).

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
		# Bench 2026-07-05: single forward missile launcher (fire 2.0), dropped at rest.
		"mounts": [{ "kind": "launcher", "marker": "", "marker_mode": "cycle", "payload_scene": "res://scenes/projectiles/drifting_missile.tscn", "aim": "forward", "fire_min": 2.0, "fire_max": 2.0, "count": 1, "no_inertia": true, "spread_deg": 0.0 }],
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "lane_cut",
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
		# Bench 2026-07-05: nose-gated aimed bolt.
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "payload": BV_AimedSniper, "aim": "forward", "fire_min": 0.3, "fire_max": 0.3, "count": 1, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": ["shielded"],
		"movement": "lane_hook",
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
		"engine": -4,   # bench 2026-07-05 (engine_override)
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "straight",   # slow straight descent
		"shoot": null,                # no hull gun — fires via the turret mounts
		"mounts": PUSH_MOUNTS,
		"bounty_override": 25,
		"hp_override": 28,
		"base_count": 2,
		"recycle": 0,                 # larger lane anchor — exit at bottom, don't loop (Roman 2026-06-08)
		"unlock_sector": 1, "unlock_depth": 1,
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn",
		"engine": -4,   # bench 2026-07-05 (engine_override)
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "straight",   # mid-speed straight descent
		"shoot": null,
		"mounts": PUSH_MOUNTS,
		"bounty_override": 25,
		"hp_override": 28,
		"base_count": 2,
		"recycle": 0,                       # anchor — exit at bottom, don't loop (Roman 2026-06-08)
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.8,
	},
	{
		"scene": "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn",
		"engine": -4,   # bench 2026-07-05 (engine_override)
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "straight",   # slow horizontal cross, lobbing shots
		"shoot": null,
		"mounts": PUSH_MOUNTS,
		"bounty_override": 25,
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
		# Bench 2026-07-05: nose-gated aimed bolt.
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "payload": BV_AimedSniper, "aim": "forward", "fire_min": 0.3, "fire_max": 0.3, "count": 1, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": ["shielded"],
		"movement": "lane_hook",
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
		# muzzles (CannonL/R at ±6). Slow, telegraphed, punishing if ignored.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn",
		"depth": "mid",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "loiter",
		# Spectre artillery — retuned via Enemy Bench (2026-06-20): bursts Privateer Bolts.
		"mounts": [{ "kind": "gun", "marker": "Cannon*", "marker_mode": "cycle", "payload": BV_PrivBolt, "aim": "straight_down", "count": 3, "burst_interval": 0.15, "fire_min": 5.0, "fire_max": 5.0 }],
		"base_count": 2,
		"hp_override": 8, "bounty_override": 18,
		"unlock_sector": 1, "unlock_depth": 2, "weight": 0.8, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	{
		# Pulse — plasma gunner. Holds a deep band and fires AIMED plasma orbs
		# (wobble 8/3, the plasma signature) from two muzzles (±8). Aimed + wobble
		# makes it the privateer pressure unit that demands active dodging.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn",
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "all", "payload": BV_PrivWave, "aim": "straight_down", "count": 3, "burst_interval": 0.1, "fire_min": 4.0, "fire_max": 4.0, "spread_deg": 0.0 }],
		"engine": -2, "depth": "mid",
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": [],
		"movement": "straight",
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
		"movement": "loiter_sweep",
		"shoot": null,
		"mounts": BEAMER_SWEEP_MOUNT,   # beam ported from enemy_beam_shooter.gd (begins on settle)
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
		"movement": "drift",
		"shoot": null,
		"mounts": BEAMER_CHASE_MOUNT,   # tracking beam, ported from enemy_beam_shooter.gd
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
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
		"shoot": null,   # bespoke tracer + cannon firing
		"base_count": 1,
		"no_scale": true,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 0.8,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
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
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
		"shoot": null,
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.5, "chaff": true,
		"conflict_tags": ["demands_focus"],
	},
	{
		# Gunship (weave) — lane-confined weave; a heavier weaver in a lane wave.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
		"shoot": null,
		"base_count": 3,
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.5, "chaff": true,
	},
	{
		# Gunship (shift) — one-way commit to an adjacent lane, then holds it.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
		"shoot": null,
		"base_count": 3,
		"unlock_sector": 2, "unlock_depth": 0, "weight": 0.5, "chaff": true,
	},
	{
		# Gunship (skirmish) — aggressive advance/retreat, raking on the hold.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn",
		"mounts": GUNSHIP_MOUNTS,
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "hunt_omni",
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
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_rocket.tscn",
		"heavy_class": "anchor",  # 32px-wide — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "medium", "tags": ["tough"],
		"movement": "straight",
		"shoot": null,   # no hull gun — fires via the launcher + gun mounts
		"mounts": ROCKET_MOUNTS,
		"bounty_override": 35,
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
		"scene": "res://scenes/enemies/core/enemy_core_bomber.tscn",
		"heavy_class": "anchor",  # 32px-wide (tall) — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": "drift",
		"shoot": null,
		"mounts": BOMBER_TAIL_MOUNT,
		"hp_override": 30,
		"bounty_override": 120,
		"base_count": 2,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.35,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_core_bomber.tscn",
		"heavy_class": "anchor",  # 32px-wide (tall) — midpoint/coda heavy-beat pool
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": "drift",
		"shoot": null,
		"mounts": BOMBER_TAIL_MOUNT,
		"hp_override": 30,
		"bounty_override": 120,
		"base_count": 3,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.35,
	},
	{
		# Thin bomber variant (Roman 2026-06-21) — lighter-framed B-220. Same anchor role + tail gun,
		# a bit less hull. Core ship (corp+priv); Livery + faction TailGunGlow auto-apply. Stats are
		# first-pass — Roman tunes.
		"scene": "res://scenes/enemies/core/enemy_core_bomber_thin.tscn",
		"heavy_class": "anchor",
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": "drift",
		"shoot": null,
		# Bench 2026-07-05: faster tail burst than the B-220 (fire 4.0 vs 3.0).
		"mounts": [{ "kind": "gun", "marker": "TurretTail", "marker_mode": "cycle", "payload": preload("res://data/bullets/ball.tres"),
			"aim": "straight_down", "count": 3, "burst_interval": 0.1, "fire_min": 4.0, "fire_max": 4.0, "spread_deg": 0.0 }],
		"hp_override": 22,
		"bounty_override": 100,
		"base_count": 2,
		"no_scale": true,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.35,
	},

	# --- RARE -------------------------------------------------------------
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_s_sapper.tscn",
		"engine": -1,
		"tier": Tier.RARE,
		"size": "small", "tags": [],
		"movement": "hunt_omni",
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
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_m_widow.tscn",
		"tier": Tier.RARE,
		"size": "medium", "tags": [],
		# High hold (Roman 2026-06-07: crystal was coming too far down) — hovers in the
		# upper band instead of the deep "loiter" hold.
		"movement": "loiter", "depth": "high",
		"mounts": [{ "kind": "gun", "marker": "", "payload": BV_SpreadPellet, "aim": "straight_down", "count": 5, "spread_deg": 36.0, "fire_min": 1.8, "fire_max": 2.6 }],
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_core_m_minelayer.tscn",
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "side_traverse",
		"shoot": null,
		"mounts": MINELAYER_MOUNTS,
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn",
		# NOT heavy-beat tagged (Roman 2026-06-04): top_dive is a transient
		# dive-through, not a presence-holding anchor. Stays a normal RARE dive squad
		# (reaction-test / direct-challenge). Heavy beats want descend-and-hold types.
		"tier": Tier.RARE,
		"size": "medium", "tags": ["tough"],
		"movement": "side_turn",
		"shoot": null,
		# Bench 2026-07-05: forward missile launcher (kind entity→launcher) — a 4-round burst.
		"mounts": [{ "kind": "launcher", "marker": "Launcher*", "marker_mode": "cycle", "payload_scene": "res://scenes/projectiles/drifting_missile.tscn", "aim": "forward", "count": 4, "burst_interval": 0.25, "fire_min": 5.0, "fire_max": 5.0, "spread_deg": 0.0 }],
		"base_count": 3,
		"unlock_sector": 1, "unlock_depth": 0,
	},
	{
		# Jet (privateer small, 2026-06-17) — fast light fighter that dives in firing from its twin
		# nose muzzles. NOTE: the scene also has LauncherL/R markers that are currently UNWIRED — add
		# a missile mount (mounts: [...]) to arm them. Movement overrides the scene's baked top_dive
		# (a retired key) with the current side_turn.
		"scene": "res://scenes/enemies/core/enemy_core_s_jet.tscn",
		"tier": Tier.UNCOMMON,
		"size": "small", "tags": [],
		"movement": "lane_cut",
		# Bench 2026-07-05: twin nose muzzles → a 3-shot forward burst of the default bullet, nose-gated.
		"mounts": [{ "kind": "gun", "marker": "", "marker_mode": "cycle", "payload": preload("res://data/bullets/ball.tres"), "aim": "forward", "count": 3, "burst_interval": 0.1, "fire_min": 1.0, "fire_max": 1.0, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"base_count": 4,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0,
	},
	{
		# Wing (privateer medium, 2026-06-17) — wide missile-dropper. Uses interceptor.gd (no-recycle
		# exit) + the reusable EmitterComponent for the drop; stats follow the medium size class.
		"scene": "res://scenes/enemies/factions/privateer/enemy_p_m_wing.tscn",
		"tier": Tier.UNCOMMON,
		"size": "large", "tags": ["tough"],
		"movement": "drift",
		"shoot": null,
		# Bench 2026-07-05: forward missile launcher (kind entity→launcher) — a 4-round nose-gated burst.
		"mounts": [{ "kind": "launcher", "marker": "Launcher*", "marker_mode": "cycle", "payload_scene": "res://scenes/projectiles/drifting_missile.tscn", "aim": "forward", "count": 4, "burst_interval": 0.1, "fire_min": 4.0, "fire_max": 4.0, "no_inertia": true, "fire_only_on_target": true, "spread_deg": 0.0 }],
		"base_count": 2,
		"unlock_sector": 1, "unlock_depth": 0, "weight": 1.0,
	},
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "medium", "tags": [],
		"movement": "drift", "depth": "mid",
		"shoot": null,
		# Bench 2026-07-05: straight-down 3-shot spread (16°) of the default bullet, dropped at rest.
		"mounts": [{ "kind": "gun", "marker": "", "marker_mode": "all", "payload": preload("res://data/bullets/ball.tres"), "aim": "straight_down", "count": 3, "fire_min": 2.5, "fire_max": 2.5, "no_inertia": true, "spread_deg": 16.0 }],
		"base_count": 1,
		# Heavy elite — sector 2+.
		"unlock_sector": 2, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/core/enemy_cruiser.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"hp_override": 28, "bounty_override": 40,   # tanky capital — was hardcoded in enemy_cruiser.gd _ready
		"movement": "loiter", "depth": "high",
		"shoot": null,
		"base_count": 1,
		"unlock_sector": 2, "unlock_depth": 0,
	},
	{
		"scene": "res://scenes/enemies/factions/corporate/enemy_c_l_hive.tscn",
		"heavy_class": "capital",  # 64px-wide (placeholder art) — coda capital pool
		"tier": Tier.RARE,
		"size": "large", "tags": [],
		"movement": "loiter", "depth": "high",
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
		"movement": "straight",  # cross the screen
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
		"movement": "straight",  # descend + hold
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
		"movement": "straight",  # slow lane drift
		"shoot": null,
		"base_count": 1,
		"no_scale": true,
		"hp_override": 32, "bounty_override": 100,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
	},
	{
		# Crusader (Roman 2026-06-20) — LARGE zealot capital, a heavier sibling of the Helix.
		# Four Helix gun turrets (Turret*) + two hull muzzles firing zealot bolts (Muzzle*),
		# plus the baked firecore drop on death. Shares enemy_firecore_cruiser.gd (clamped to
		# ~1px/f capital speed); bigger stats via the overrides below. Slow loiter gun-platform.
		# First-pass tier/stat gating — Roman tunes (pull this entry if it should stay bench-only).
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_l_crusader.tscn",
		"mounts": CRUSADER_MOUNTS,
		"engine": -4, "recycle": 0,
		"heavy_class": "capital",
		"tier": Tier.RARE,
		"size": "huge", "tags": ["tough"],
		"movement": "straight",  # descend + hold as a gun platform
		"shoot": null,
		"base_count": 1,
		"no_scale": true,
		"hp_override": 60, "bounty_override": 180,
		"unlock_sector": 3, "unlock_depth": 1, "weight": 0.4,
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

	# --- Zealot units promoted from the Enemy Bench (2026-06-20) — configs from enemy_bench.json.
	{
		# Censer Frigate — nose wave-projectors (armed from the bench 2026-07-05; engine stays 0 —
		# the bench's -1 was already reverted here to avoid the creep sub-rung).
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_censer.tscn",
		"engine": -1, "tier": Tier.COMMON, "size": "medium", "tags": [],   # bench 2026-07-05 (engine_override)
		"movement": "straight", "shoot": null, "base_count": 2, "recycle": 0,
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "all", "payload": BV_ZealotWave, "aim": "straight_down", "fire_min": 3.0, "fire_max": 3.0, "count": 2, "burst_interval": 0.15, "no_inertia": true, "spread_deg": 0.0 }],
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.5,
	},
	{
		# Crook — rapid-fire zealot laser fighter.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_crook.tscn",
		"tier": Tier.COMMON, "size": "medium", "tags": [],
		"movement": "straight", "shoot": null, "base_count": 3, "recycle": 0,
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotLaser, "aim": "forward", "fire_min": 0.5, "fire_max": 0.5, "count": 4, "spread_deg": 0.0 }],
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.7,
	},
	{
		# Cross Gunship — omni-thrust twin-laser gunboat.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_cross.tscn",
		"engine": -1, "tier": Tier.COMMON, "size": "medium", "tags": [],   # bench 2026-07-05 (engine_override)
		"movement": "hunt_omni", "shoot": null, "base_count": 2, "recycle": 0,
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotBolt, "aim": "forward", "fire_min": 1.0, "fire_max": 1.0, "count": 4, "spread_deg": 0.0 }],
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.6,
	},
	{
		# Pilgrim — dual plasma + wing rockets. (bench 2026-07-05: small hull + engine -1 = same ~60 speed.)
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_pilgrim.tscn",
		"engine": -1, "tier": Tier.UNCOMMON, "size": "small", "tags": [],
		"movement": "straight", "shoot": null, "base_count": 2, "recycle": 0,
		"mounts": [
			{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotLaser, "aim": "forward", "fire_min": 0.5, "fire_max": 0.5, "count": 1, "spread_deg": 0.0 },
			{ "kind": "launcher", "marker": "Launcher*", "marker_mode": "cycle", "payload_scene": "res://scenes/projectiles/enemy_rocket.tscn", "aim": "forward", "fire_min": 1.2, "fire_max": 1.2, "count": 1, "spread_deg": 0.0 },
		],
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
	},
	{
		# Rebuker — slow, maneuverable, forward zealot lasers.
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_rebuker.tscn",
		"engine": 0, "tier": Tier.COMMON, "size": "medium", "tags": [],   # held at 60 (was -1; base drop would push to creep)
		"movement": "straight", "shoot": null, "base_count": 2, "recycle": 0,
		"mounts": [{ "kind": "gun", "marker": "Muzzle*", "marker_mode": "cycle", "payload": BV_ZealotLaser, "aim": "straight_down", "fire_min": 0.5, "fire_max": 0.5, "count": 1, "spread_deg": 0.0 }],
		"unlock_sector": 1, "unlock_depth": 1, "weight": 0.6,
	},
	{
		# Spear Frigate — charged firecore BEAM. The beam_config drives its charge animation (the scene
		# bakes a BeamChargeVisual component on its ChargeMask). aim_mode 4 = TRACK_LOCK (tracks between
		# shots, holds aim while charging+firing for a fair dodge window).
		"scene": "res://scenes/enemies/factions/zealot/enemy_z_s_spear.tscn",
		"tier": Tier.UNCOMMON, "size": "medium", "tags": [],
		"movement": "loiter", "shoot": null, "base_count": 2, "recycle": 0,
		"mounts": [{ "kind": "beam", "marker": "Muzzle", "beam_config": {
			"aim_mode": 4, "target_group": "player",
			"idle_time": 0.8, "windup_time": 1.2, "firing_time": 0.7, "cooldown_time": 1.2,
			"reach": 320.0, "dps": 4.0, "hit_radius": 8.0, "autostart": true,
		} }],
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
	},
	{
		# Tyrant (enemy_frigate) — supremacy broadside capital. Fires a rolling naval broadside out its
		# player-facing flank (GunLeft1..5 / GunRight1..5 markers on the scene).
		"scene": "res://scenes/enemies/factions/supremacy/enemy_frigate.tscn",
		"tier": Tier.RARE, "size": "large", "tags": ["tough"],
		"movement": "side_traverse",
		"base_count": 1, "no_scale": true, "fire_min": 0.35, "fire_max": 0.5,
		"hp_override": 16, "bounty_override": 40,
		"unlock_sector": 2, "unlock_depth": 1, "weight": 0.5,
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


# Is this roster entry ARMED — i.e. does it project a threat at the player while it's
# on the field? Used by the wave generator's "shooter-density ramp" (early levels lean
# on UNARMED chaff; armed chaff arrives sparingly and in smaller clusters). Inspects the
# RAW entry dict (cheap — no scene load / MountSpec build), so it stays generic over every
# enemy and faction with zero per-enemy special-casing.
#
# ARMED when ANY of:
#   - "shoot" is a non-null shoot key (legacy Weapon slot — fires bullets)
#   - "mounts" holds a firing hardpoint: a gun/turret/launcher/beam/ring (all fire
#     projectiles or a beam), OR an ENTITY dropper that emits WHILE TRAVELLING
#     (trigger cadence/timer/start — bomblet/mine/firecore trails threaten the lane).
#   - "emitters" holds the same kind of active (non-death) emitter.
#
# NOT armed (harmless volume — the bulk the ramp leaves untouched):
#   - no shoot / mounts / emitters at all (plain rammer chaff — Dart, Shiv, Drifter…)
#   - ONLY a death-trigger entity/emitter (a death-scatter is a one-shot on kill, not
#     sustained on-field pressure — it doesn't make the unit read as a "shooter"; killing
#     it is the player's choice). If Roman wants death-scatterers counted as armed, flip
#     _DEATH_EMIT_COUNTS_ARMED below.
const _FIRING_MOUNT_KINDS := ["gun", "turret", "launcher", "beam", "ring"]
const _DEATH_EMIT_COUNTS_ARMED := false   # tuning knob: treat pure death-scatter droppers as armed?

static func entry_is_armed(entry: Dictionary) -> bool:
	if entry == null or entry.is_empty():
		return false
	# Legacy shoot slot.
	if entry.get("shoot", null) != null:
		return true
	# Mount hardpoints.
	var mounts: Variant = entry.get("mounts", null)
	if mounts is Array:
		for m in mounts:
			if m is Dictionary and _mount_dict_is_threat(m):
				return true
	# Generalized emitters (interceptor-style drops).
	var emitters: Variant = entry.get("emitters", null)
	if emitters is Array:
		for em in emitters:
			if em is Dictionary and _emitter_dict_is_threat(em):
				return true
	return false


# A mount dict threatens the player if it's a projectile/beam hardpoint, or an ENTITY
# dropper that emits while travelling (not a pure death-scatter — see entry_is_armed).
static func _mount_dict_is_threat(m: Dictionary) -> bool:
	var kind: String = String(m.get("kind", "gun"))
	if kind in _FIRING_MOUNT_KINDS:
		return true
	if kind == "entity":
		var trig: String = String(m.get("trigger", "cadence"))
		if trig == "death":
			return _DEATH_EMIT_COUNTS_ARMED
		return true   # cadence/timer/start — spawns a hazard on the field
	return false


# An emitter dict threatens the player unless it's a pure death-scatter (mirrors the
# ENTITY-mount rule; emitters default to the "timer" trigger).
static func _emitter_dict_is_threat(em: Dictionary) -> bool:
	var trig: String = String(em.get("trigger", "timer"))
	if trig == "death":
		return _DEATH_EMIT_COUNTS_ARMED
	return true


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

	var loco: Dictionary = resolve_locomotion(entry, size)
	return {
		"max_health": hp,
		"shield_charges": shield_charges,
		"bounty_value": bounty,
		"recycle_passes": recycle,
		"move_speed": loco["move_speed"],
		"weight": loco["weight"],
		"turn_rate": loco["turn_rate"],
		"accel": loco["accel"],
		"depth_bp": loco["depth_bp"],
	}


# Resolve the chassis locomotion stats for an entry: size base + a per-entry `engine` rung offset
# (shifts linear speed only) + optional raw overrides (move_speed/weight/turn_rate/accel) + a
# default `depth` band. Pure numbers (no tree / no Zones→Y), so it is headless-safe. move_speed is
# clamped to the rung grid and snapped. depth_bp is band_progress (0..1), or -1 = "pattern default".
static func resolve_locomotion(entry: Dictionary, size: String = "") -> Dictionary:
	var sz: String = size if size != "" else String(entry.get("size", "medium"))
	var loco: Dictionary = SIZE_LOCOMOTION.get(sz, SIZE_LOCOMOTION["medium"])
	var move_speed: float = float(loco["base_rung"]) + float(int(entry.get("engine", 0))) * Clarity.RUNG_STEP
	if entry.has("move_speed"):
		move_speed = float(entry["move_speed"])
	move_speed = Clarity.snap_to_rung(clampf(move_speed, Clarity.CREEP_SPEED, Clarity.ABS_MAX_SPEED))
	# Depth: an explicit entry "depth" wins; otherwise inherit the band from a legacy banded
	# movement identity (loiter_high / drift_mid / side_traverse_low → high / mid / low) so the
	# key-collapse preserves each enemy's hold/cross height without per-entry edits.
	var depth_spec: Variant = entry.get("depth", "")
	if depth_spec == null or String(depth_spec) == "":
		depth_spec = _legacy_depth_for(entry)
	return {
		"move_speed": move_speed,
		"weight": float(entry.get("weight", loco["weight"])),
		"turn_rate": float(entry.get("turn_rate", loco["turn_rate"])),
		"accel": float(entry.get("accel", loco["accel"])),
		"depth_bp": Zones.depth_to_bp(depth_spec, -1.0),
	}


# Default depth band for an entry whose movement identity is a legacy banded key (the *_high/_mid/
# _low suffix that collapsed into the depth axis). "" when the enemy has no banded identity.
# Inert as of the 2026-06-20 shape-key cleanup — every banded enemy now carries an explicit
# "depth" on its ENTRY (which wins in resolve_locomotion), so this returns "" for all live data.
# Kept as a fallback for hand-authored entries / old saved JSON that still use a banded identity.
static func _legacy_depth_for(entry: Dictionary) -> String:
	# str() not String(): the String() constructor only accepts String/StringName/NodePath, so a
	# non-string "movement"/"scene" entry value (e.g. a Resource) throws "Invalid call 'String'
	# constructor". str() stringifies any Variant — a non-banded value just yields a non-matching
	# string → "" (the correct fallback). (Crash found via the combat repro, 2026-06-22.)
	var id: String = PatternEligibility.identity_for(str(entry.get("scene", "")))
	if id == "":
		id = str(entry.get("movement", ""))
	if id.ends_with("_high"):
		return "high"
	if id.ends_with("_mid"):
		return "mid"
	if id.ends_with("_low"):
		return "low"
	return ""


# Legacy movement-key aliases (locomotion refactor 2026-06-19): the speed/depth-variant keys
# collapsed to shape-only keys once speed/depth became chassis/formation-owned. As of the 2026-06-20
# cleanup NO live producer feeds a legacy key here — the committed eligibility DATA + roster ENTRIES
# are all shape keys. Retained defensively as a load-time net for old saved eligibility JSON or
# hand-authored entries that still reference a pre-collapse key.
const MOVEMENT_ALIASES := {
	"straight_crawl": "straight", "straight_slow": "straight", "straight_medium": "straight",
	"straight_fast": "straight", "straight_reflex": "straight",
	"drift_low": "drift", "drift_mid": "drift", "drift_high": "drift",
	"loiter_low": "loiter", "loiter_mid": "loiter", "loiter_high": "loiter",
	"side_traverse_high": "side_traverse", "side_traverse_mid": "side_traverse",
	"side_traverse_low": "side_traverse",
	"side_dive": "side_turn",   # collapsed 2026-06-22 — side_dive was SideTurn w/ a shorter advance; one pattern now
	"pendulum": "skirmish_pendulum",   # renamed 2026-06-22 — grouped under the skirmish family
}


# Build a fresh movement-pattern Resource for an entry. Each spawned enemy
# duplicates this so the pattern can keep per-instance state.
static func make_movement(entry: Dictionary) -> Resource:
	# Resolve the movement KEY via the eligibility matrix: the entry's own movement (identity)
	# unless it opts into variety ("vary": true) — then a flat-random eligible key. Behavior-
	# preserving until eligibility is expanded + an entry opts in (pattern_eligibility.gd).
	var key: String = PatternEligibility.resolve(entry)
	key = MOVEMENT_ALIASES.get(key, key)   # collapse legacy speed/depth-variant keys to shapes
	# Hand-authored flight paths (Path Editor, 2026-07-06): "path_<name>" keys resolve through the
	# baked library instead of the shape match below. See authored_path_library.gd.
	if AuthoredPathLibrary.is_path_key(key):
		return AuthoredPathLibrary.resolve_key(key)
	match key:
		# --- STRAIGHT: pure descent. Speed is chassis-owned now (size base + engine); the old
		# straight_crawl/slow/medium/fast/reflex keys collapsed here (locomotion refactor). ---
		"straight":
			return _straight()
		"straight_charge":
			# Slow telegraphed entry, then accelerate hard in the fire zone (was lane_charge).
			return LaneCharge.new()
		# --- SKIRMISH loops (replaces the broken advance_retreat) ---
		"skirmish_loop":
			return _skirmish(Skirmish.Shape.LOOP)
		"skirmish_figure8":
			return _skirmish(Skirmish.Shape.FIGURE8)
		# --- DRIFT (tank hold + jiggle). Hold DEPTH is the chassis/formation depth axis now;
		# drift_low/mid/high collapsed here (locomotion refactor). ---
		"drift":
			return Drift.new()   # hover_y vestigial — enemy.depth_bp drives the hold height
		"lane_weave":
			# Weaver (m6 §13, lane_path engine) — wobble WITHIN its own lane while
			# descending. Lane-confined: ~10px swing < half lane width (12), never
			# crosses into a neighbor. (P2: lane_path is the production lateral engine.)
			var m = LanePath.new()
			m.shape = LanePath.Shape.WEAVE
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
			m.mirrored = randf() < 0.5
			return m
		"lane_shift":
			# Shifter (m6 §13) — descend, then a one-way COMMIT to an adjacent lane
			# (only if free), then hold the destination. The HOOK = Shifter decision.
			# Live as of 2026-06-07: the Gunship (shift) roster variant uses this.
			var m = LanePath.new()
			m.shape = LanePath.Shape.HOOK
			m.shift_lanes = 1
			m.shift_duration = 0.7
			m.mirrored = randf() < 0.5
			return m
		"lane_hook":
			# Down a lane, curve into the adjacent lane at the fire-zone midpoint, then climb
			# back up and off the TOP. For droppers — drop the volley, then turn and burn.
			var m = LanePath.new()
			m.shape = LanePath.Shape.DIVE_RETURN
			m.shift_lanes = 1
			m.mirrored = randf() < 0.5
			return m
		"lane_cut":
			# Down a lane, curve LEFT/RIGHT at the fire-zone midpoint, then run horizontally
			# off the side (Roman 2026-06-08).
			var m = LanePath.new()
			m.shape = LanePath.Shape.LANE_CUT
			m.mirrored = randf() < 0.5
			return m
		"loiter":
			# Holder (m6 §13). Hover into the fire band, hold with a gentle bob/sway, then
			# accelerate away. Hold DEPTH is the chassis/formation depth axis now (loiter_low/mid/high
			# collapsed here); enter/exit speed are chassis-owned. Timing/jiggle stay pattern shape.
			var m = Loiter.new()
			m.loiter_time = 3.0
			return m
		"side_turn":
			# Advance horizontally in, rounded-turn down into the lane, descend to exit.
			# (`side_dive` collapsed into this 2026-06-22 — it was the same pattern with a shorter
			# advance, and the descent speed is chassis-owned, so there was no real second version.
			# `side_dive` now aliases to `side_turn` in MOVEMENT_ALIASES.)
			return SideTurn.new()
		"side_traverse":
			# Slow horizontal cross (Minelayer). Cross DEPTH is the chassis/formation depth axis now
			# (side_traverse_high/mid/low collapsed here); cross speed is chassis-owned.
			return _side_traverse()
		"hunt_beeline":
			# Player-tracking pursuit — threatens, shouldn't connect (was beeline).
			var m = BeelinePlayer.new()
			return m
		"hunt_omni":
			# Omni-thrust vector roamer — holds stand-off range + strafes (was omni).
			# Leaves after a few passes instead of harassing forever (Roman 2026-06-11).
			var omt = OmniThrust.new()
			omt.max_passes = 3
			return omt
		"skirmish_pendulum":
			# Dual-band vertical ping-pong diver w/ aim-fire dwell (ported from crystal).
			# (Renamed from "pendulum" 2026-06-22 to group it with the skirmish family; the old
			# key aliases to this in MOVEMENT_ALIASES.)
			return Pendulum.new()
		"proximity_chase":
			# Drift straight until near the player, then activate a chase (smart mine/bomblet).
			return ProximityChase.new()
		"loiter_sweep":
			# Descend to a band, then rake L↔R (beam shooter SWEEP locomotion). Renamed from
			# "beam_sweep" 2026-06-09 — behavior unchanged.
			return LoiterSweep.new()
	# Default: a readable medium straight.
	return _straight()


# --- make_movement helpers (Roman 2026-06-08 pattern overhaul) ---
static func _straight() -> Resource:
	# Speed is chassis-owned (enemy.move_speed); StraightDown just descends.
	return StraightDown.new()


static func _skirmish(shape: int) -> Resource:
	var m = Skirmish.new()
	m.shape = shape
	return m


static func _side_traverse() -> Resource:
	var m = SideTraverse.new()
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


const _MOUNT_KIND := {"gun": 0, "turret": 1, "launcher": 2, "beam": 3, "entity": 4, "ring": 5}   # MountSpec.Kind
const _MOUNT_AIM := {"straight_down": 0, "toward_center": 1, "at_player": 2, "forward": 3, "backward": 4, "left": 5, "right": 6}  # MountSpec.Aim
const _MOUNT_MODE := {"all": 0, "cycle": 1, "inward": 2, "outward": 3}         # MountSpec.MarkerMode
const _HARDPOINT_TRIGGER := {"cadence": 0, "timer": 0, "start": 1, "death": 2}  # MountSpec.Trigger (ENTITY)

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
	m.no_inertia = bool(d.get("no_inertia", m.kind == MountSpec.Kind.ENTITY))  # ENTITY drops at rest by default; guns carry inertia
	m.payload_delay_ms = float(d.get("payload_delay_ms", 0.0))      # Payload Delay (Phase 1)
	m.deviation_deg = float(d.get("deviation_deg", 0.0))           # shot inaccuracy (2026-07-04)
	m.max_fires = int(d.get("max_fires", 0))                       # GUN/LAUNCHER fire cap per pass
	m.volleys = int(d.get("volleys", 1))                          # spread layers: repeat the fan N times
	m.volley_gap = float(d.get("volley_gap", 0.0))               # stagger between volleys
	m.homing_rate = float(d.get("homing_rate", 0.0))
	m.wobble_amplitude = float(d.get("wobble_amplitude", 0.0))
	m.wobble_frequency = float(d.get("wobble_frequency", 0.0))
	m.fire_zone_gated = bool(d.get("fire_zone_gated", false))
	m.fire_only_on_target = bool(d.get("fire_only_on_target", false))
	m.fire_aim_tol_deg = float(d.get("fire_aim_tol_deg", 18.0))
	var _fpp: Variant = d.get("fire_path_phases", null)
	if _fpp is Array:
		m.fire_path_phases = PackedFloat32Array(_fpp)
	m.fire_beat_synced = bool(d.get("fire_beat_synced", true))
	m.fire_on_phase = String(d.get("fire_on_phase", ""))
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
	# ENTITY (Phase 3): trigger + emit fields when a hardpoint spawns a scene on start/cadence/death.
	m.trigger = int(_HARDPOINT_TRIGGER.get(String(d.get("trigger", "cadence")), 0))
	m.emit_scatter = float(d.get("scatter", 0.0))
	m.emit_chance = float(d.get("emit_chance", d.get("chance", 1.0)))
	m.max_emits = int(d.get("max_emits", 0))
	m.band_only = bool(d.get("band_only", false))
	m.attach_to_enemy = bool(d.get("attach_to_enemy", d.get("attach", false)))
	m.emit_tag = String(d.get("tag", ""))
	m.emit_sfx = String(d.get("sfx", ""))
	# RING (Phase C): an OrbitComponent delivery — orbiting payloads released on death/leave.
	m.orbit_mode = int(d.get("orbit_mode", 0))
	m.release_speed = float(d.get("release_speed", 140.0))
	m.host_drift = float(d.get("host_drift", 0.0))
	m.release_sfx = String(d.get("release_sfx", "enemy_blaster"))
	m.rings = _resolve_rings(d.get("rings", []))
	return m


# Resolve a ring-spec list for a RING mount: load any String `scene` path into a PackedScene (roster
# GDScript already preloads; bench-JSON rings arrive as paths). `variant` is passed through as-is.
static func _resolve_rings(src) -> Array:
	if not (src is Array):
		return []
	var out: Array = []
	for r in src:
		if not (r is Dictionary):
			continue
		var ring: Dictionary = (r as Dictionary).duplicate()
		var sc = ring.get("scene", null)
		if sc is String and sc != "":
			ring["scene"] = load(sc)
		out.append(ring)
	return out


# ---- Emitters (behavior components: drop/spawn a payload scene on a trigger) ----------------------
# Mirrors make_mounts: builds EmitterComponents from an entry's optional "emitters" key (dict-list).
# Returns [] when absent (every existing entry unchanged). Used by wave_generator (production) + the
# Enemy Bench. An emitter is the generalized form of the interceptor's missile-drop (Roman 2026-06-17).
const EmitterComponentC = preload("res://scripts/enemies/components/emitter_component.gd")
# Phase 2 (2026-07-03): roster/bench emitters realize as ENTITY MountComponents (the unified path);
# EmitterComponent survives only for the faction firecore overlay. String trigger -> MountSpec.Trigger
# (CADENCE=0, START=1, DEATH=2) — note "timer" -> CADENCE (the fire-interval emit timer).
const MountComponentC = preload("res://scripts/enemies/mounts/mount_component.gd")
const _EMIT_TRIGGER_K := {"start": 1, "timer": 0, "death": 2}
# Friendly payload names → scene paths (the Enemy Bench dropdown picks from these).
const EMITTABLE := {
	"Missile":  "res://scenes/projectiles/drifting_missile.tscn",
	"Mine":     "res://scenes/enemies/enemy_mine.tscn",
	"Bomblet":  "res://scenes/enemies/enemy_bomblet.tscn",
	"Firecore": "res://scenes/enemies/factions/zealot/firecore_hazard.tscn",
}


static func make_emitters(entry: Dictionary) -> Array:
	var listed: Variant = entry.get("emitters", [])
	return make_emitter_specs(listed) if listed is Array else []


# Shared dict → EmitterComponent converter, also used by the Enemy Bench preview. FRESH per call.
static func make_emitter_specs(dicts: Array) -> Array:
	var out: Array = []
	for d in dicts:
		if d is Dictionary:
			var e = _emitter_from_dict(d)
			if e != null:
				out.append(e)
	return out


static func _emitter_from_dict(d: Dictionary) -> Resource:
	# An emitter is now an ENTITY MountSpec realized by a MountComponent (Phase 2). Fields map 1:1;
	# `drop` -> no_inertia (drop=true => leave at rest / don't inherit the enemy's velocity).
	var s = MountSpec.new()
	s.kind = MountSpec.Kind.ENTITY
	s.trigger = int(_EMIT_TRIGGER_K.get(String(d.get("trigger", "timer")), 0))
	# payload: an EMITTABLE name, or a direct res:// scene path / PackedScene.
	var pay: Variant = d.get("payload", "")
	if pay is String:
		var path: String = String(EMITTABLE.get(pay, pay))   # name → path, else treat the string as a path
		if path != "" and ResourceLoader.exists(path):
			s.payload_scene = load(path)
	elif pay is PackedScene:
		s.payload_scene = pay
	s.count = int(d.get("count", 1))
	var cad: float = float(d.get("cadence", 2.0))
	s.fire_interval_min = cad
	s.fire_interval_max = cad
	s.emit_chance = float(d.get("chance", 1.0))
	s.emit_scatter = float(d.get("spread", 0.0))
	s.attach_to_enemy = bool(d.get("attach", d.get("attach_to_enemy", false)))
	s.emit_tag = String(d.get("tag", ""))
	s.max_emits = int(d.get("max_emits", 0))
	s.band_only = bool(d.get("band_only", false))
	s.emit_sfx = String(d.get("sfx", ""))
	s.no_inertia = bool(d.get("drop", true))   # drop default true = at rest; false = launch w/ velocity
	var mc = MountComponentC.new()
	mc.spec = s
	return mc


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
