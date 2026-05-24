extends RefCounted
class_name WaveGenerator

# Dynamic wave generator. Produces a LevelData based on:
#   sector_depth          — sector index (1 = first sector, 2+ = deeper into
#                           endless mode). Affects baseline difficulty.
#   level_index_in_sector — 0 = first combat node since the sector reset;
#                           grows with each combat node completed.
#   is_boss               — true when generating the boss-arena level.
#
# Roman, 2026-05-16:
#   - First combat = 1 enemy type, 2 waves, modest counts.
#   - Each subsequent combat in the sector adds a wave, a new enemy type, or
#     bumps counts.
#   - Boss levels insert one extra lead-in wave BEFORE the boss.
#   - Rarity weights shift toward uncommon/rare as the player goes deeper
#     into the sector.
#   - A fresh sector after the boss resets level_index_in_sector but the
#     first combat there is guaranteed 2 waves (handled by caller).

const Roster = preload("res://scripts/levels/enemy_roster.gd")
const WaveSpec = preload("res://scripts/levels/wave_def.gd")
const LevelData = preload("res://scripts/levels/level_def.gd")
const BossSweep = preload("res://scripts/enemies/patterns/boss_sweep.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

# Boss roster. Generator picks one weighted by sector_depth and the run
# seed. Each entry exports its own scene + a label for diagnostics.
const BOSS_ROSTER := [
	{
		"scene": "res://scenes/enemies/boss.tscn",            # Commander (minion + black-hole)
		"label": "Commander",
		"banner": "HIGH VALUE TARGET INCOMING",
	},
	{
		"scene": "res://scenes/enemies/boss_reaver.tscn",     # Lash (dive sweeper)
		"label": "Lash",
		"banner": "LASH INBOUND",
	},
	{
		"scene": "res://scenes/enemies/boss_sentinel.tscn",   # Aegis (multi-part shielded turret)
		"label": "Aegis",
		"banner": "AEGIS ENGAGED",
	},
	{
		"scene": "res://scenes/enemies/boss_howler.tscn",     # Howler (anchored ring/burst)
		"label": "Howler",
		"banner": "HOWLER INBOUND",
	},
	{
		"scene": "res://scenes/enemies/boss_voidmaw.tscn",    # Voidmaw (drifting BHs)
		"label": "Voidmaw",
		"banner": "VOIDMAW EMERGES",
	},
	{
		"scene": "res://scenes/enemies/boss_spinwright.tscn", # Spinwright (beam sweep + ring deflect)
		"label": "Spinwright",
		"banner": "SPINWRIGHT ACTIVE",
	},
	{
		"scene": "res://scenes/enemies/boss_conductor.tscn",  # Conductor (final — satellites + transform)
		"label": "Conductor",
		"banner": "THE CONDUCTOR ARRIVES",
	},
]


# Public entry point. Returns a fully-built LevelData.
static func build(sector_depth: int, level_index_in_sector: int, is_boss: bool) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(sector_depth, level_index_in_sector, is_boss)

	var level = LevelData.new()
	if is_boss:
		level.level_name = "Sector %d — Commander" % sector_depth
		level.waves = _build_boss_waves(rng, sector_depth, level_index_in_sector)
	else:
		level.level_name = "Sector %d — %d" % [sector_depth, level_index_in_sector + 1]
		level.waves = _build_combat_waves(rng, sector_depth, level_index_in_sector)
	return level


# Wave count target for a given level index. First node = 2, then +1 per
# subsequent combat node, soft-capped at 5 to keep run length reasonable.
static func _wave_count_for(level_index: int) -> int:
	return clamp(2 + level_index, 2, 5)


# Combat level. Rolls _wave_count_for(level_index) waves, each populated by
# a roll against the depth-weighted rarity table.
static func _build_combat_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	var n_waves: int = _wave_count_for(level_index)
	var waves: Array = []
	var used: Array = []  # entries already used in this level (variety)
	for i in n_waves:
		var entry: Dictionary = _pick_entry(rng, sector_depth, level_index, used)
		used.append(entry)
		var w = _make_wave_spec(rng, entry, sector_depth, level_index, i)
		# First wave gets the "ENGAGE" / sector announce; later waves silent so
		# we don't pop banner after banner on a single level.
		if i == 0:
			w.announce_text = ""  # uses default "WAVE 1 / N"
		else:
			w.silent = false  # banner each wave so player can pace
		waves.append(w)
	return waves


# Boss level: one lead-in wave then the boss. Roman, 2026-05-16: "Boss levels
# always add one new wave, and it's always before the boss itself."
static func _build_boss_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	# Lead-in: a regular combat wave at the current depth.
	var lead_entry: Dictionary = _pick_entry(rng, sector_depth, level_index, [])
	var w_lead = _make_wave_spec(rng, lead_entry, sector_depth, level_index, 0)

	# Boss wave: 1 boss rolled from the roster. Each boss scene applies its
	# own HP / behavior overrides in _ready(); we just pick which scene the
	# director instantiates.
	var boss_entry: Dictionary = _pick_boss(rng, sector_depth)
	var w_boss = WaveSpec.new()
	w_boss.enemy_scene = load(boss_entry["scene"])
	w_boss.count = 1
	w_boss.spawn_interval = 1.0
	w_boss.spawn_delay = 5.0
	w_boss.announce_text = String(boss_entry.get("banner", "HIGH VALUE TARGET INCOMING"))
	w_boss.formation = 3  # CENTER_OUT
	var bm = BossSweep.new()
	# hover_y is owned by boss.gd's @export boss_hover_y (per-boss). The
	# pattern's hover_y here is just a fallback for the duplicate(); boss
	# overwrites it in start().
	bm.enter_speed = 140.0
	bm.sweep_amplitude = 240.0
	bm.sweep_frequency = 0.3
	w_boss.movement_override = bm
	var bs = SpreadShot.new()
	bs.bullet_scene = EnemyBullet
	bs.bullet_count = 5
	bs.spread_degrees = 50.0
	w_boss.shoot_pattern_override = bs
	w_boss.fire_interval_min = 0.9
	w_boss.fire_interval_max = 1.4
	return [w_lead, w_boss]


# Roll a roster entry weighted by tier probability for the current depth.
# `exclude` is a list of entries already used in this level (skipped if any
# unused entries remain).
static func _pick_entry(rng: RandomNumberGenerator, sector_depth: int, level_index: int, exclude: Array) -> Dictionary:
	var tier := _roll_tier(rng, sector_depth, level_index)
	var pool: Array = Roster.entries_of(tier)
	# Fall back to other tiers if the rolled tier is empty.
	if pool.is_empty():
		pool = Roster.entries_of(Roster.Tier.UNCOMMON)
	if pool.is_empty():
		pool = Roster.entries_of(Roster.Tier.COMMON)
	# Avoid repeating an enemy already in this level when we have room.
	var fresh: Array = []
	for e in pool:
		if not exclude.has(e):
			fresh.append(e)
	if not fresh.is_empty():
		pool = fresh
	return pool[rng.randi() % pool.size()]


# Tier rolls. The deeper into the sector, the more uncommon/rare lean.
# Sector depth nudges the weights modestly so endless mode keeps creeping
# upward but a fresh sector still opens calm.
static func _roll_tier(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> int:
	var common: float = 100.0
	var uncommon: float = 0.0
	var rare: float = 0.0
	# Per-level shift:
	if level_index >= 1:
		common -= 30.0
		uncommon += 30.0
	if level_index >= 3:
		common -= 20.0
		uncommon += 5.0
		rare += 15.0
	if level_index >= 5:
		common -= 15.0
		uncommon += 5.0
		rare += 10.0
	# Sector depth bonus — each extra sector pushes a little more uncommon/rare.
	var sd_bonus: float = float(max(sector_depth - 1, 0))
	common = max(common - sd_bonus * 5.0, 0.0)
	rare += sd_bonus * 3.0
	uncommon += sd_bonus * 2.0
	var total: float = common + uncommon + rare
	if total <= 0.0:
		return Roster.Tier.COMMON
	var roll: float = rng.randf() * total
	if roll < common:
		return Roster.Tier.COMMON
	roll -= common
	if roll < uncommon:
		return Roster.Tier.UNCOMMON
	return Roster.Tier.RARE


# Build a WaveSpec for a given roster entry, scaled by sector depth + level
# index. wave_index_in_level just shifts spawn_delay so consecutive waves don't
# collide.
static func _make_wave_spec(rng: RandomNumberGenerator, entry: Dictionary, sector_depth: int, level_index: int, wave_index_in_level: int) -> WaveSpec:
	var w = WaveSpec.new()
	w.enemy_scene = load(entry["scene"])
	# Count scales with level_index + sector_depth. Capped so rarer enemies
	# don't overflow the playfield.
	var base: int = int(entry.get("base_count", 4))
	var scale: float = 1.0 + 0.15 * float(level_index) + 0.08 * float(max(sector_depth - 1, 0))
	var count: int = int(round(base * scale))
	w.count = clamp(count, 1, base * 2)
	w.spawn_interval = 0.4 + rng.randf_range(0.0, 0.25)
	w.spawn_delay = 0.5 + 0.6 * float(wave_index_in_level)
	w.formation = rng.randi() % 4
	w.movement_override = Roster.make_movement(entry)
	var sp: Resource = Roster.make_shoot(entry)
	if sp != null:
		w.shoot_pattern_override = sp
	if entry.has("fire_min"):
		w.fire_interval_min = float(entry["fire_min"])
	if entry.has("fire_max"):
		w.fire_interval_max = float(entry["fire_max"])
	var stats: Dictionary = Roster.compose_stats(entry)
	w.max_health = stats["max_health"]
	w.bounty_value = stats["bounty_value"]
	if stats["shield_charges"] > 0:
		w.shield_charges = stats["shield_charges"]
	if stats["recycle_passes"] >= -1:
		w.recycle_passes = stats["recycle_passes"]
	return w


# Pick a boss from BOSS_ROSTER. For now a flat random — could be weighted
# by sector_depth later if Roman wants a specific climb.
static func _pick_boss(rng: RandomNumberGenerator, _sector_depth: int) -> Dictionary:
	# Dev override: Run.forced_boss_scene wins. Consumed once.
	var run_node = Engine.get_main_loop().root.get_node_or_null("Run") if Engine.get_main_loop() else null
	if run_node and String(run_node.forced_boss_scene) != "":
		var forced: String = String(run_node.forced_boss_scene)
		run_node.forced_boss_scene = ""
		for e in BOSS_ROSTER:
			if String(e["scene"]) == forced:
				return e
		# Path didn't match the roster — synthesize a minimal entry.
		return {"scene": forced, "label": "Forced", "banner": "DEV BOSS"}
	if BOSS_ROSTER.is_empty():
		return {"scene": "res://scenes/enemies/boss.tscn", "banner": "BOSS"}
	return BOSS_ROSTER[rng.randi() % BOSS_ROSTER.size()]


# Same inputs produce the same level. Lets the player retry from the same
# sector node without a different roll, and keeps testing reproducible.
static func _stable_seed(sector_depth: int, level_index: int, is_boss: bool) -> int:
	var s: int = sector_depth * 100003
	s += level_index * 7919
	s += 5 if is_boss else 0
	return s
