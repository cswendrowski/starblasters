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

# Per-boss chaff conflict tags. Lead-in waves drop chaff carrying any of
# these tags so the boss's signature pressure doesn't overlap a chaff
# pattern that demands the same player attention budget. Empty / unlisted
# scene = no filtering.
# Wave intermingling — probability the Nth combat wave in a level mixes
# two enemy types. Index = level_index_in_sector, clamped to last entry.
# Sector_depth adds +0.05 per sector past the first. Clamped to [0, 0.85].
# Wave 0 of every level is never mixed (calm intro). See _should_intermingle.
const WAVE_INTERMINGLE_PROBS := [0.0, 0.20, 0.40, 0.60, 0.75]

# Affinity table — symmetric pairs that "go together" thematically. When a
# rolled pair is on this table, accept it immediately. Otherwise re-roll
# the second pick once with 50% chance. Scene-path keyed.
const WAVE_AFFINITY := {
	"res://scenes/enemies/enemy_minelayer.tscn": ["res://scenes/enemies/enemy_hunter_drone.tscn"],
	"res://scenes/enemies/enemy_hunter_drone.tscn": ["res://scenes/enemies/enemy_minelayer.tscn"],
	"res://scenes/enemies/enemy_drifter.tscn": ["res://scenes/enemies/enemy_dart.tscn", "res://scenes/enemies/enemy_weaver.tscn"],
	"res://scenes/enemies/enemy_dart.tscn": ["res://scenes/enemies/enemy_drifter.tscn"],
	"res://scenes/enemies/enemy_skirmisher.tscn": ["res://scenes/enemies/enemy_firecore.tscn"],
	"res://scenes/enemies/enemy_firecore.tscn": ["res://scenes/enemies/enemy_skirmisher.tscn"],
	"res://scenes/enemies/enemy_cutter.tscn": ["res://scenes/enemies/enemy_hover.tscn"],
	"res://scenes/enemies/enemy_hover.tscn": ["res://scenes/enemies/enemy_cutter.tscn"],
	"res://scenes/enemies/enemy_weaver.tscn": ["res://scenes/enemies/enemy_drifter.tscn"],
}

# Per-wave HP bonus from prior wave-clears within the current sector. Each
# cleared combat in a sector adds BONUS_HP_PER_WAVE to every chaff's max_health
# in subsequent waves, capped at BONUS_HP_CAP. Bosses scale separately and
# don't take this bonus on their own wave; their lead-in chaff DOES.
const BONUS_HP_PER_WAVE: int = 1
const BONUS_HP_CAP: int = 5

const BOSS_LEADIN_CONFLICTS := {
	"res://scenes/enemies/boss_voidmaw.tscn": ["dumb_shot", "wide_dodge"],
	"res://scenes/enemies/boss_howler.tscn": ["aimed_or_spread"],
	"res://scenes/enemies/boss_reaver.tscn": ["aimed_or_spread"],   # Lash
	"res://scenes/enemies/boss_sentinel.tscn": ["demands_focus"],   # Aegis
	"res://scenes/enemies/boss_spinwright.tscn": ["wide_dodge"],
	"res://scenes/enemies/boss_conductor.tscn": ["demands_focus", "aimed_or_spread"],
}


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
		# Wave 0 is never mixed (calm intro). Otherwise roll P(mix).
		var mix: bool = i > 0 and _should_intermingle(level_index, sector_depth, rng)
		if mix:
			var pair: Array = _pick_pair(rng, sector_depth, level_index, used)
			used.append(pair[0])
			used.append(pair[1])
			var sub_a = _make_wave_spec(rng, pair[0], sector_depth, level_index, i)
			var sub_b = _make_wave_spec(rng, pair[1], sector_depth, level_index, i)
			# Density formula: count_each = max(2, round(base_count * 0.5)).
			# Exception: base_count == 1 (Rare-tier solo enemies) — keep full count
			# on both sub-waves for the intentional late-wave threat spike.
			var base_a: int = int(pair[0].get("base_count", 4))
			var base_b: int = int(pair[1].get("base_count", 4))
			# no_scale entries (e.g. gunship trio) must not be halved — their
			# role assignment logic depends on the exact count being preserved.
			if base_a > 1 and not bool(pair[0].get("no_scale", false)):
				sub_a.count = maxi(2, int(round(float(sub_a.count) * 0.5)))
			if base_b > 1 and not bool(pair[1].get("no_scale", false)):
				sub_b.count = maxi(2, int(round(float(sub_b.count) * 0.5)))
			# Opposite formations so streams come from opposite sides.
			# 50/50 which side leads.
			if rng.randf() < 0.5:
				sub_a.formation = WaveSpec.Formation.TOP_LEFT_TO_RIGHT
				sub_b.formation = WaveSpec.Formation.TOP_RIGHT_TO_LEFT
			else:
				sub_a.formation = WaveSpec.Formation.TOP_RIGHT_TO_LEFT
				sub_b.formation = WaveSpec.Formation.TOP_LEFT_TO_RIGHT
			# Both sub-waves share spawn_delay (already set by _make_wave_spec from
			# wave_index_in_level); second sub-wave's stream is stretched 1.3× so
			# the two streams interleave instead of stacking.
			sub_b.spawn_delay = sub_a.spawn_delay
			# Stretch sub_b's stream relative to sub_a so they interleave
			# instead of stacking. Use sub_a's interval as the anchor.
			sub_b.spawn_interval = sub_a.spawn_interval * 1.3
			# One banner per logical wave — sub_b is silent.
			sub_b.announce_text = ""
			sub_b.silent = true
			if i == 0:
				sub_a.announce_text = ""
			waves.append(sub_a)
			waves.append(sub_b)
		else:
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


# Returns true if this wave should be a mixed two-enemy wave.
# P(mix) = WAVE_INTERMINGLE_PROBS[clamp(level_index, ...)] + 0.05*(sector_depth-1)
# Clamped to [0, 0.85]. Caller is responsible for skipping wave 0.
static func _should_intermingle(level_index: int, sector_depth: int, rng: RandomNumberGenerator) -> bool:
	var idx: int = clampi(level_index, 0, WAVE_INTERMINGLE_PROBS.size() - 1)
	var p: float = float(WAVE_INTERMINGLE_PROBS[idx]) + 0.05 * float(max(sector_depth - 1, 0))
	p = clampf(p, 0.0, 0.85)
	return rng.randf() < p


# Pick two entries for an intermingled wave. Second pick excludes the first
# pick's conflict_tags (existing safety) and is tier-capped at UNCOMMON if the
# first pick was RARE (max one Rare per mixed wave). Affinity bias: if the
# resulting pair isn't in WAVE_AFFINITY, with 50% chance re-roll the second
# pick once. Returns [first, second].
static func _pick_pair(rng: RandomNumberGenerator, sector_depth: int, level_index: int, used: Array) -> Array:
	var first: Dictionary = _pick_entry(rng, sector_depth, level_index, used)
	var first_tags: PackedStringArray = PackedStringArray(first.get("conflict_tags", []))
	var tier_cap: int = Roster.Tier.RARE
	if int(first.get("tier", Roster.Tier.COMMON)) == Roster.Tier.RARE:
		tier_cap = Roster.Tier.UNCOMMON
	# Block the first pick itself from being picked again as second.
	var exclude_second: Array = used.duplicate()
	exclude_second.append(first)
	var second: Dictionary = _pick_entry(rng, sector_depth, level_index, exclude_second, first_tags, tier_cap)
	# Affinity bias — if pair not in affinity table, 50% chance to re-roll once.
	if not _is_affinity_pair(first, second) and rng.randf() < 0.5:
		var second2: Dictionary = _pick_entry(rng, sector_depth, level_index, exclude_second, first_tags, tier_cap)
		second = second2
	return [first, second]


static func _is_affinity_pair(a: Dictionary, b: Dictionary) -> bool:
	var pa: String = String(a.get("scene", ""))
	var pb: String = String(b.get("scene", ""))
	if not WAVE_AFFINITY.has(pa):
		return false
	var partners: Array = WAVE_AFFINITY[pa]
	return partners.has(pb)


# Boss level: 2-4 escalating lead-in waves then the boss. Lead-in chaff
# filters out enemies whose conflict_tags overlap the boss's own pressure
# signature (BOSS_LEADIN_CONFLICTS). Final lead-in is thinned and re-bannered
# so the boss arrival reads cleanly.
static func _build_boss_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	var boss_entry: Dictionary = _pick_boss(rng, sector_depth)
	var conflict_tags: PackedStringArray = PackedStringArray(
		BOSS_LEADIN_CONFLICTS.get(boss_entry["scene"], []))
	var n_leadin: int = clampi(1 + sector_depth, 2, 4)  # S1=2, S2=3, S3+=4
	var used: Array = []
	var waves: Array = []
	for i in n_leadin:
		var entry: Dictionary = _pick_entry(rng, sector_depth, level_index + i, used, conflict_tags)
		used.append(entry)
		var w = _make_wave_spec(rng, entry, sector_depth, level_index + i, i, true)
		if i == n_leadin - 1:
			# Thin the final lead-in and re-banner so the boss arrival reads cleanly.
			w.count = maxi(2, int(w.count / 2))
			w.announce_text = "BOSS APPROACHING"
		waves.append(w)
	var w_boss = _make_boss_wave(boss_entry)
	w_boss.spawn_delay = 5.0 - 0.5 * float(sector_depth - 1)  # 4.5/4.0/3.5
	waves.append(w_boss)
	return waves


# Build the boss WaveSpec. Boss scene applies its own HP / behavior
# overrides in _ready(); we just pick which scene the director instantiates.
static func _make_boss_wave(boss_entry: Dictionary) -> WaveSpec:
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
	return w_boss


# Roll a roster entry weighted by tier probability for the current depth.
# `exclude` is a list of entries already used in this level (skipped if any
# unused entries remain).
# `exclude_tags` filters out entries whose conflict_tags intersect — used by
# boss lead-in waves to avoid chaff that overlaps the boss's pressure
# signature. If the filter empties the pool, falls back to the unfiltered
# pool so we never softlock generation.
static func _pick_entry(rng: RandomNumberGenerator, sector_depth: int, level_index: int, exclude: Array, exclude_tags: PackedStringArray = PackedStringArray(), max_tier: int = Roster.Tier.RARE) -> Dictionary:
	var tier := _roll_tier(rng, sector_depth, level_index)
	if tier > max_tier:
		tier = max_tier
	var pool: Array = Roster.entries_of(tier)
	# Fall back to other tiers if the rolled tier is empty.
	if pool.is_empty() and Roster.Tier.UNCOMMON <= max_tier:
		pool = Roster.entries_of(Roster.Tier.UNCOMMON)
	if pool.is_empty():
		pool = Roster.entries_of(Roster.Tier.COMMON)
	# Conflict-tag filter for boss lead-ins.
	if not exclude_tags.is_empty():
		var tag_filtered: Array = []
		for e in pool:
			var etags: Array = e.get("conflict_tags", [])
			var clash: bool = false
			for t in etags:
				if exclude_tags.has(String(t)):
					clash = true
					break
			if not clash:
				tag_filtered.append(e)
		if not tag_filtered.is_empty():
			pool = tag_filtered
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
static func _make_wave_spec(rng: RandomNumberGenerator, entry: Dictionary, sector_depth: int, level_index: int, wave_index_in_level: int, is_boss_leadin: bool = false) -> WaveSpec:
	var w = WaveSpec.new()
	w.enemy_scene = load(entry["scene"])
	# Count scales with level_index + sector_depth. Capped so rarer enemies
	# don't overflow the playfield.
	var base: int = int(entry.get("base_count", 4))
	# no_scale: true locks count to base_count (e.g. gunship trio needs
	# exactly 3 so the role-assignment logic receives the right indices).
	var count: int
	if bool(entry.get("no_scale", false)):
		count = base
	else:
		# Sector-depth scaling has moved to the explicit chaff_bonus below (was
		# `+ 0.08 * (sector_depth-1)` here; removed to avoid double-counting with
		# the additive +1/sector bonus for COMMON chaff).
		var scale: float = 1.0 + 0.15 * float(level_index)
		count = int(round(base * scale))
		count = clamp(count, 1, base * 2)
		# CHAFF DENSITY BUMP (designer 2026-05-24): chaff waves +50% count so they
		# run 50% longer AND have ~50% more enemies on screen at once (spawn_interval
		# unchanged, so per-enemy onscreen lifetime is constant → more concurrent).
		# Boss lead-ins keep their tuned count (they're separately thinned in
		# _build_boss_waves for the final lead-in). Mixed-wave 0.5× halving is
		# applied by _build_combat_waves AFTER this returns, so mixed waves are
		# still smaller than singles but proportionally larger than before the bump.
		if not is_boss_leadin and base > 1:
			count = int(ceil(float(count) * 1.5))
	# Per-sector chaff bonus (designer 2026-05-24 economy pass): COMMONs get
	# +1 enemy per sector beyond the first (S1=+0, S2=+1, S3=+2). UNCOMMON +
	# RARE get nothing extra here — they pick up difficulty via the per-wave
	# HP bonus below. Boss lead-ins are exempt; they're tuned by _build_boss_waves.
	var chaff_bonus: int = 0
	var roster_tier: int = int(entry.get("tier", Roster.Tier.COMMON))
	if roster_tier == Roster.Tier.COMMON and not is_boss_leadin:
		chaff_bonus = maxi(sector_depth - 1, 0)
	count += chaff_bonus
	# Widen the clamp ceiling by chaff_bonus so the bonus isn't silently eaten
	# by the existing `base * 2` cap on dense COMMON waves.
	count = clampi(count, 1, base * 2 + chaff_bonus)
	w.count = count
	# Per-wave HP bonus from prior wave-clears in this sector. Read Run via the
	# main-loop root (matches _pick_boss above). Boss lead-ins don't take this
	# bump (their boss scales per the boss design pass); their chaff still gets
	# the chaff_bonus above.
	if not is_boss_leadin:
		var combats: int = 0
		var mloop = Engine.get_main_loop()
		if mloop and mloop.root:
			var run_node = mloop.root.get_node_or_null("Run")
			if run_node and "combats_in_sector" in run_node:
				combats = int(run_node.combats_in_sector)
		w.health_bonus = clampi(combats * BONUS_HP_PER_WAVE, 0, BONUS_HP_CAP)
	w.spawn_interval = 0.4 + rng.randf_range(0.0, 0.25)
	w.spawn_delay = 0.5 + 0.6 * float(wave_index_in_level)
	w.formation = rng.randi() % 4
	w.movement_override = Roster.make_movement(entry)
	# S-curve mirror coin-flip — designer 2026-05-24: top-down traversing
	# patterns should support mirrored variants for variety. Coin-flip here
	# (after Roster.make_movement) so the mirror flag rides on the wave's
	# movement_override Resource and both sub-wave streams (or both tandem
	# pair members) inherit it for in-concert motion.
	if w.movement_override != null and "mirrored" in w.movement_override:
		w.movement_override.mirrored = rng.randf() < 0.5
	# Tandem formation roll — designer 2026-05-24: 25% chance at level_index >= 2
	# (chaff only, not boss lead-ins). Gated to top-down descent patterns so we
	# don't pair up side-cutters or loiterers. The director spawns pairs at
	# CENTER ± tandem_offset_x simultaneously; force even count so no lone
	# trailing enemy.
	var mv_key: String = String(entry.get("movement", ""))
	var tandem_eligible: bool = mv_key in [
		"straight", "firecore_straight", "drifter_straight",
		"fast_straight", "s_curve",
	]
	if tandem_eligible and not is_boss_leadin and level_index >= 2 and rng.randf() < 0.25:
		w.formation = WaveSpec.Formation.TOP_TANDEM_PAIRS
		if (w.count % 2) == 1:
			w.count += 1
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
