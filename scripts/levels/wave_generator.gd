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
# Weapons 3b (2026-06-13): the boss sweep config fires via the unified Weapon (was SpreadShot).
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")
const FormationShapesC = preload("res://scripts/levels/formation_shapes.gd")

# Per-boss chaff conflict tags. Lead-in waves drop chaff carrying any of
# these tags so the boss's signature pressure doesn't overlap a chaff
# pattern that demands the same player attention budget. Empty / unlisted
# scene = no filtering.
# Chaos ramp (Roman 2026-06-01). Per-node chaff add caps at this; combined with
# the cross-sector term, the grand total chaff bonus caps at CHAFF_BONUS_TOTAL_CAP.
const COMBAT_DEPTH_CHAFF_MAX := 3
const CHAFF_BONUS_TOTAL_CAP := 4

# Wave intermingling — probability the Nth combat wave in a level mixes
# two enemy types. Index = level_index_in_sector, clamped to last entry.
# Sector_depth adds +0.05 per sector past the first. Clamped to [0, 0.85].
# Wave 0 of every level is never mixed (calm intro). See _should_intermingle.
const WAVE_INTERMINGLE_PROBS := [0.0, 0.30, 0.55, 0.75, 0.85]

# Affinity table — symmetric pairs that "go together" thematically. When a
# rolled pair is on this table, accept it immediately. Otherwise re-roll
# the second pick once with 50% chance. Scene-path keyed.
const WAVE_AFFINITY := {
	# Cut-unit pairs (cutter/drifter/hover/spitter/weaver) removed 2026-06-20 — those ships were
	# retired; only survivors remain on the affinity table.
}

# Per-wave HP bonus from prior wave-clears within the current sector. Each
# cleared combat in a sector adds BONUS_HP_PER_WAVE to every chaff's max_health
# in subsequent waves, capped at BONUS_HP_CAP. Bosses scale separately and
# don't take this bonus on their own wave; their lead-in chaff DOES.
const BONUS_HP_PER_WAVE: int = 1
const BONUS_HP_CAP: int = 5

const BOSS_LEADIN_CONFLICTS := {
	"res://scenes/enemies/bosses/boss_voidmaw.tscn": ["dumb_shot", "wide_dodge"],
	"res://scenes/enemies/bosses/boss_howler.tscn": ["aimed_or_spread"],
	"res://scenes/enemies/bosses/boss_reaver.tscn": ["aimed_or_spread"],   # Lash
	"res://scenes/enemies/bosses/boss_sentinel.tscn": ["demands_focus"],   # Aegis
	"res://scenes/enemies/bosses/boss_spinwright.tscn": ["wide_dodge"],
	"res://scenes/enemies/bosses/boss_conductor.tscn": ["demands_focus", "aimed_or_spread"],
}


# Boss roster. Generator picks one weighted by sector_depth and the run
# seed. Each entry exports its own scene + a label for diagnostics.
const BOSS_ROSTER := [
	{
		"scene": "res://scenes/enemies/bosses/boss.tscn",            # Commander (minion + black-hole)
		"label": "Commander",
		"banner": "HIGH VALUE TARGET INCOMING",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_reaver.tscn",     # Lash (dive sweeper)
		"label": "Lash",
		"banner": "LASH INBOUND",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_sentinel.tscn",   # Aegis (multi-part shielded turret)
		"label": "Aegis",
		"banner": "AEGIS ENGAGED",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_howler.tscn",     # Howler (anchored ring/burst)
		"label": "Howler",
		"banner": "HOWLER INBOUND",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_voidmaw.tscn",    # Voidmaw (drifting BHs)
		"label": "Voidmaw",
		"banner": "VOIDMAW EMERGES",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_spinwright.tscn", # Spinwright (beam sweep + ring deflect)
		"label": "Spinwright",
		"banner": "SPINWRIGHT ACTIVE",
	},
	{
		"scene": "res://scenes/enemies/bosses/boss_conductor.tscn",  # Conductor (final — satellites + transform)
		"label": "Conductor",
		"banner": "THE CONDUCTOR ARRIVES",
	},
]


# Public entry point. Returns a fully-built LevelData.
# (Kept as the flat artifact for tests + sim_wavegen + LevelData-manipulating callers
# like the Bounty Board extra-waves and the dev "Test Level" .tres path.)
static func build(sector_depth: int, level_index_in_sector: int, is_boss: bool, faction: int = -1) -> LevelData:
	# M6b: restrict the enemy pool to the active faction (universal + faction homes) for
	# the duration of this synchronous build. -1 = no faction (boss/hazard/legacy). Save +
	# restore the prior filter (review P2) instead of hard-clearing, so a nested build()
	# can't wipe an outer build's filter.
	var _prev_faction: int = Roster.get_faction_filter()
	Roster.set_faction_filter(faction)
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(sector_depth, level_index_in_sector, is_boss)

	var level = LevelData.new()
	if is_boss:
		level.level_name = "Sector %d — Commander" % sector_depth
		level.waves = _build_boss_waves(rng, sector_depth, level_index_in_sector)
	else:
		level.level_name = "Sector %d — %d" % [sector_depth, level_index_in_sector + 1]
		level.waves = _build_combat_waves(rng, sector_depth, level_index_in_sector)
	Roster.set_faction_filter(_prev_faction)   # restore (nested-build safe)
	return level


# Native CombatScore emission (M5 end-state). The producer-side score the conductor
# performs directly via WaveDirector.start_score, instead of the director lifting flat
# LevelData through ScoreAdapter at runtime. Same content as build(), assembled into
# the Wave->Phrase structure by the shared score builder. THIS is the seam M6 enriches
# (faction tints, telegraphs, native wall/filler authoring) — author phrases here
# rather than inferring them from flat WaveSpecs.
static func build_score(sector_depth: int, level_index_in_sector: int, is_boss: bool, faction: int = -1) -> CombatScore:
	var score := ScoreAdapter.from_level_data(build(sector_depth, level_index_in_sector, is_boss, faction))
	# Native phrase authoring on top of the lifted flat score (the seam the bridge names). ESCORT is
	# the first multi-TYPE formation — a heavy core + chaff screen in ONE phrase, which the flat
	# WaveSpec→one-phrase adapter path can't express. Boss levels keep their tuned lead-in.
	if not is_boss:
		_maybe_inject_escort(score, sector_depth, level_index_in_sector, faction)
	return score


# Wave count target. 5-8 waves per level (streaming model, M5): the conductor
# blends them into one continuous stream, so more waves = a longer, fuller level.
# Base 5, +1 per node into the sector and +1 per sector depth, soft-capped at 8.
static func _wave_count_for(sector_depth: int, level_index: int) -> int:
	return clampi(5 + level_index + (sector_depth - 1), 5, 8)


# Level enemy budget (M5): the soft total headcount the level streams toward (the
# conductor caps how many are on screen at once). Opener ~140 -> mature ~300 ->
# deep ceiling 350. Composition wins ties. TUNE via tools/test_budget.gd.
static func _level_budget(sector_depth: int, level_index: int) -> int:
	return clampi(int(round(140.0 + 25.0 * level_index + 35.0 * (sector_depth - 1))), 140, 350)


# Streaming concurrency cap (M5, bridge §1.2/§8): the on-screen non-hazard density
# ceiling the conductor enforces. The budget (above) is the TOTAL the level streams
# toward; this cap is the RATE — how many of that total are alive at once. Ramps
# 12 (shallow opener, stays readable) -> 16 (deep) with +1 per node and +1 per
# sector. The director consumes this via main.gd; default export is the fallback.
static func cap_for(sector_depth: int, level_index: int) -> int:
	return clampi(12 + level_index + (sector_depth - 1), 12, 16)


# Scale the level's CHAFF waves so the total approaches the budget, leaving discrete beats (heavies /
# capped flocks / accents) at their authored counts. `chaff_flags` is parallel to `waves` — true =
# scalable chaff. (Roman 2026-06-27: was keyed on base_count >= 4, which MISCLASSIFIED low-base
# uncommon chaff as elite and left it to trickle at count 2-3. The explicit flag scales it densely.)
static func _apply_budget(waves: Array, chaff_flags: Array, sector_depth: int, level_index: int) -> void:
	if waves.is_empty():
		return
	var target: int = _level_budget(sector_depth, level_index)
	var elite_total: int = 0
	var chaff_idx: Array = []
	var chaff_raw: int = 0
	for i in waves.size():
		if i < chaff_flags.size() and bool(chaff_flags[i]):
			chaff_idx.append(i)
			chaff_raw += int(waves[i].count)
		else:
			elite_total += int(waves[i].count)
	if chaff_idx.is_empty() or chaff_raw <= 0:
		return
	var chaff_budget: int = maxi(0, target - elite_total)
	var scale: float = float(chaff_budget) / float(chaff_raw)
	for i in chaff_idx:
		waves[i].count = maxi(2, int(round(float(waves[i].count) * scale)))


# Combat level (Roman 2026-06-10 restructure): exactly 5 WAVES, each broken into 3 sub-wave
# compositions that flow continuously, then a BREATHER before the next wave (avoids the old 5-8
# run-on stream). Per wave:
#   START  — a sweeping chaff entry; NON-silent, so it opens a new ScoreWave (the wave banner).
#   MIDDLE — the bulk; another chaff type, opposite sweep. Silent (attaches to the wave).
#   END    — the capstone: a heavy anchor that "shows itself" (or the boss-substitute heavy on the
#            final wave); falls back to a tight chaff wall when no heavy is unlocked. Silent.
# The score adapter groups each START+MIDDLE+END trio into ONE ScoreWave (silent-chaining) and
# injects a breather between waves (ScoreAdapter.BREATHER_EVERY == 1). Budget scaling fills the
# chaff sub-waves to the level headcount; heavies (low base_count) stay discrete.
const COMBAT_WAVE_COUNT: int = 5

# GEOMETRIC CAPSTONE (conductor readability pass, 2026-06-23). When a wave's END beat has no heavy,
# cap it with a held geometric flock (formation_shapes.gd) this often, else the classic shifting
# WALL/PINCER. A flock is a DISCRETE readable burst — its count is held to [MIN,MAX] and it's kept
# out of the chaff budget pool so it stays a formation instead of being scaled into a big column. A
# coherent straight descent (lane-pinned) makes the painted shape hold. Tune CHANCE up freely; this
# is the seam more authored/parametric shapes plug into later.
const GEOMETRIC_CAPSTONE_CHANCE: float = 0.6
const GEOMETRIC_FLOCK_MIN: int = 8
const GEOMETRIC_FLOCK_MAX: int = 12

# ACCENT STING (conductor readability pass, 2026-06-23). The generator builds big chaff blobs and
# heavy/flock capstones but has no MICRO-phrase — the audit's missing "2-3 enemy crossing sting" that
# punctuates the rhythm between bulk waves (the authored cross-pairs, e.g. shift_cross_pair). After a
# non-finale wave's capstone, this often appends a tiny side-crossing burst (SIDE_ALTERNATING +
# side_traverse → one unit from each edge, scissoring across the upper band on the existing crosser
# dispatch). Silent (no banner), DISCRETE (count 2-3, excluded from the chaff budget), so it reads as
# a quick grace-note before the breather, not another wall. Tune CHANCE freely.
const ACCENT_CHANCE: float = 0.35

# ESCORT (audit follow-on, 2026-06-23). Per-level chance build_score splices a heavy-core-plus-chaff-
# screen convoy into a mid wave. Discrete spectacle, lockstep-clamped to the slow core. Pre-stack gap
# matches the geometric/authored row spacing. Tune CHANCE freely.
const ESCORT_CHANCE: float = 0.4
const ESCORT_ROW_GAP: float = 40.0

static func _build_combat_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	# PALETTE (Roman 2026-06-27): the whole level draws from a SMALL subset of the roster, not the full
	# pool per beat (which produced 9-15 distinct types/level). The bulk beats cycle the chaff list; the
	# capstone uses the level's one heavy. Kitchen-sink (full pool) is reserved for the boss lead-in.
	var palette: Dictionary = _pick_palette(rng, sector_depth, level_index)
	var chaff_types: Array = palette["chaff"]
	var heavy_type: Dictionary = palette["heavy"]
	if chaff_types.is_empty():
		return []   # roster misconfig guard (should never happen — basic chaff is unlock 0)
	var waves: Array = []
	# Parallel to `waves`: true = a chaff bulk wave that _apply_budget scales to the headcount; false =
	# a DISCRETE beat (heavy / capped flock / accent) left at its authored count.
	var chaff_flags: Array = []
	for i in COMBAT_WAVE_COUNT:
		var lead_lr: bool = (i % 2 == 0)
		var is_finale: bool = (i == COMBAT_WAVE_COUNT - 1)
		# START — a chaff entry from the palette; opens the wave (banner). Cycles the palette for
		# variety within the subset.
		var e_start: Dictionary = chaff_types[i % chaff_types.size()]
		var s_start = _make_wave_spec(rng, e_start, sector_depth, level_index, i)
		s_start.formation = WaveSpec.Formation.TOP_LEFT_TO_RIGHT if lead_lr else WaveSpec.Formation.TOP_RIGHT_TO_LEFT
		s_start.silent = false        # opens a new ScoreWave -> one banner per wave
		s_start.announce_text = ""    # default "WAVE n / 5"
		s_start.spawn_delay = 0.5
		_apply_force_formation(s_start, e_start)
		waves.append(s_start); chaff_flags.append(true)
		# MIDDLE — the bulk; a DIFFERENT palette chaff (same type if the palette has only one), opposite
		# sweep. Budget-scaled, so even a low-base uncommon chaff fills out densely (no trickle).
		var e_mid: Dictionary = chaff_types[(i + 1) % chaff_types.size()]
		var s_mid = _make_wave_spec(rng, e_mid, sector_depth, level_index, i)
		s_mid.formation = WaveSpec.Formation.TOP_RIGHT_TO_LEFT if lead_lr else WaveSpec.Formation.TOP_LEFT_TO_RIGHT
		s_mid.silent = true
		s_mid.spawn_delay = 0.35
		_apply_force_formation(s_mid, e_mid)
		waves.append(s_mid); chaff_flags.append(true)
		# END — the capstone: the level's heavy on the finale (always) and ~60% of waves 1-3; else a
		# held flock / shifting wall of palette chaff.
		var want_heavy: bool = is_finale or (i >= 1 and rng.randf() < 0.6)
		if want_heavy and not heavy_type.is_empty():
			var s_end = _make_wave_spec(rng, heavy_type, sector_depth, level_index, i)
			# Floor of 2 so a medium heavy never arrives as a lone, slow, unexciting single — a real
			# anchor PAIR reads as a beat. A genuinely big capital (large/huge) may still come solo.
			var hi: int = 3 if is_finale else 2
			var lo: int = 1 if String(heavy_type.get("size", "")) in ["large", "huge"] else 2
			s_end.count = clampi(int(s_end.count), lo, hi)
			s_end.formation = WaveSpec.Formation.TOP_CENTER_OUT
			s_end.silent = true
			s_end.spawn_delay = 0.35
			waves.append(s_end); chaff_flags.append(false)   # discrete anchor
		else:
			# No heavy this beat — cap the wave with a held GEOMETRIC FLOCK (formation_shapes) most of
			# the time, else the classic shifting WALL / PINCER. See GEOMETRIC_CAPSTONE_CHANCE above.
			var e_end: Dictionary = chaff_types[rng.randi() % chaff_types.size()]
			var s_end2 = _make_wave_spec(rng, e_end, sector_depth, level_index, i)
			s_end2.silent = true
			s_end2.spawn_delay = 0.35
			# Geometric only when the entry doesn't demand its own formation (e.g. Burner's beam-pair).
			if not e_end.has("force_formation") and rng.randf() < GEOMETRIC_CAPSTONE_CHANCE:
				s_end2.shape_override = FormationShapesC.SHAPES[rng.randi() % FormationShapesC.SHAPES.size()]
				s_end2.count = clampi(int(s_end2.count), GEOMETRIC_FLOCK_MIN, GEOMETRIC_FLOCK_MAX)
				# Coherent straight descent so the lane-pinned shape holds rigidly as it enters.
				s_end2.movement_override = Roster.make_movement({"movement": "straight"})
				waves.append(s_end2); chaff_flags.append(false)   # discrete capped flock
			else:
				s_end2.formation = WaveSpec.Formation.WALL if lead_lr else WaveSpec.Formation.PINCER
				_apply_force_formation(s_end2, e_end)
				waves.append(s_end2); chaff_flags.append(true)    # scaled chaff wall
		# ACCENT — a quick crossing sting punctuates the tail of some non-finale waves (see ACCENT_CHANCE).
		if not is_finale and rng.randf() < ACCENT_CHANCE:
			var s_acc = _make_accent_wave(rng, chaff_types[rng.randi() % chaff_types.size()], sector_depth, level_index, i)
			if s_acc != null:
				waves.append(s_acc); chaff_flags.append(false)   # discrete sting
	_apply_budget(waves, chaff_flags, sector_depth, level_index)
	return waves


# Per-level unit PALETTE (Roman 2026-06-27): a small subset of the eligible roster the whole level
# draws from. {"chaff": Array of chaff-tagged entries, "heavy": one heavy entry ({} if none unlocked)}.
# Chaff count grows with depth (1 at the opener → 3 deep) so an early node features one swarm + a
# heavy, a later node a few. Force-formation chaff (Burner etc.) is excluded — it needs its own beat.
static func _pick_palette(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Dictionary:
	var chaff_pool: Array = []
	for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON]:
		for e in Roster.entries_eligible(tier, sector_depth, level_index):
			if bool(e.get("chaff", false)) and not e.has("force_formation"):
				chaff_pool.append(e)
	_shuffle(chaff_pool, rng)
	# 2 chaff types at the opener (avoids a whole level of ONE unit), up to 3 deep — a tight subset.
	# Kitchen-sink (the full pool) is the boss lead-in's job, not a normal node's.
	var n_chaff: int = clampi(2 + level_index, 2, 3)
	var chaff: Array = []
	for e in chaff_pool:
		if chaff.size() >= n_chaff:
			break
		if not chaff.has(e):
			chaff.append(e)
	# Fallback: no chaff-tagged entries unlocked (shouldn't happen) — take any common.
	if chaff.is_empty():
		var any: Array = Roster.entries_eligible(Roster.Tier.COMMON, sector_depth, level_index)
		if any.is_empty():
			any = Roster.entries_of(Roster.Tier.COMMON)
		if not any.is_empty():
			chaff.append(any[rng.randi() % any.size()])
	var prefer_capital: bool = (level_index >= 1 or sector_depth >= 2)
	var heavy: Dictionary = _pick_heavy(rng, sector_depth, level_index, [], prefer_capital)
	return {"chaff": chaff, "heavy": heavy}


# Seeded Fisher-Yates in place (the generator's rng, so the palette reproduces per run+node).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t = arr[i]; arr[i] = arr[j]; arr[j] = t


# Build a tiny crossing-sting WaveSpec (the audit's "2-3 enemy accent") from a palette chaff `entry`,
# forced to a side-alternating cross (one from each edge, scissoring across the upper band via the
# director's existing crosser dispatch). Returns null if the entry is empty or demands its own
# formation (e.g. Burner's beam-pair), so the accent is simply skipped that beat. Silent + count 2-3.
static func _make_accent_wave(rng: RandomNumberGenerator, entry: Dictionary, sector_depth: int, level_index: int, wave_index: int) -> WaveSpec:
	var e: Dictionary = entry
	if e.is_empty() or e.has("force_formation"):
		return null
	var w = _make_wave_spec(rng, e, sector_depth, level_index, wave_index)
	w.count = 2 + (rng.randi() % 2)   # 2 or 3
	w.formation = WaveSpec.Formation.SIDE_ALTERNATING
	# Force the horizontal cross so the sting reads regardless of the entry's own movement.
	w.movement_override = Roster.make_movement({"movement": "side_traverse"})
	# Pin to the high band so it cuts cleanly across the TOP (away from the player's lane) instead of
	# riding the chaff's natural depth — the crosser dispatch reads depth_override for the cross latitude.
	w.depth_override = Zones.depth_to_bp("high", w.depth_override)
	w.silent = true
	w.spawn_delay = 0.4
	w.spawn_interval = 0.12   # quick one-two
	return w


# ESCORT injection (audit follow-on). Occasionally splice a heavy-core-plus-chaff-screen formation
# into a mid wave of the score. This is the first MIXED-TYPE formation: a single FORMATION phrase
# carrying two roster entries (heavy + chaff), which the flat WaveSpec→one-phrase adapter path can't
# produce — so it's authored here on the CombatScore. The screen is lockstep-clamped to the slow core
# so it descends WITH the heavy instead of outrunning it (the real lockstep payoff). Seeded from the
# node's stable stream (distinct sub-stream) so a retry reproduces it. Mutates `score` in place.
static func _maybe_inject_escort(score: CombatScore, sector_depth: int, level_index: int, faction: int) -> void:
	if score == null or score.waves.size() < 3:
		return
	# Keep the calm opener (sector 1, first node) escort-free.
	if sector_depth <= 1 and level_index <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(sector_depth, level_index, false) ^ 0x5C027   # distinct sub-stream
	if rng.randf() >= ESCORT_CHANCE:
		return
	# Pick the core + screen entries under the level's faction filter (mirrors build()).
	var prev_faction: int = Roster.get_faction_filter()
	Roster.set_faction_filter(faction)
	var heavy: Dictionary = _pick_heavy(rng, sector_depth, level_index, [], false)   # prefer anchor (movement-slot)
	var chaff: Dictionary = _pick_entry(rng, sector_depth, level_index, [], PackedStringArray(), Roster.Tier.COMMON, "")
	Roster.set_faction_filter(prev_faction)
	# Skip if nothing suitable, or either pick demands its own formation (e.g. Burner's beam-pair).
	if heavy.is_empty() or chaff.is_empty() or heavy.has("force_formation") or chaff.has("force_formation"):
		return
	var ph := _build_escort_phrase(rng, heavy, chaff, sector_depth, level_index)
	if ph == null:
		return
	# Drop into a mid wave — never the opener or the finale — as that wave's final formation phrase.
	var idx: int = clampi(int(score.waves.size() / 2), 1, maxi(1, score.waves.size() - 2))
	score.waves[idx].phrases.append(ph)


# Assemble the escort FORMATION phrase: fill the screen cells from `chaff` and the core cells from
# `heavy` (formation_shapes.escort layout), pre-stack the rows above the top edge so the convoy
# descends in holding shape, and lockstep-clamp the whole burst to the slowest (the core). Shape
# &"authored" routes it to director._dispatch_authored (the mixed-type pre-stacked burst path). null
# if too few specs resolve.
static func _build_escort_phrase(rng: RandomNumberGenerator, heavy: Dictionary, chaff: Dictionary, sector_depth: int, level_index: int) -> Phrase:
	var layout: Dictionary = FormationShapesC.escort(1 + (rng.randi() % 2))   # 1-2 cores
	var core_cells: Array = layout["core"]
	var screen_cells: Array = layout["screen"]
	var max_row: int = 0
	for c in core_cells:
		max_row = maxi(max_row, int(c.y))
	for c in screen_cells:
		max_row = maxi(max_row, int(c.y))
	var specs: Array = []
	for c in screen_cells:
		var s = _escort_spec(rng, chaff, c, max_row, sector_depth, level_index)
		if s != null:
			specs.append(s)
	for c in core_cells:
		var s = _escort_spec(rng, heavy, c, max_row, sector_depth, level_index)
		if s != null:
			specs.append(s)
	if specs.size() < 2:
		return null
	# LOCKSTEP — clamp the fast chaff to the SLOW core's speed so the screen holds around the heavy
	# instead of outrunning it (mirrors authored_patterns._lock_to_slowest; the audit's #1, finally
	# load-bearing now that a generated formation is mixed-speed).
	_lock_specs_to_slowest(specs)
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.shape = &"authored"
	ph.specs = specs
	return ph


# One escort member: a count-1 spec for `entry` pinned to its cell's lane + pre-stacked spawn_y, with
# a straight descent so it holds its lane as the convoy advances. Reuses _make_wave_spec so the unit
# keeps its real stats/weapon/components. (A bespoke heavy with no movement slot keeps its own
# locomotion but still takes the locked move_speed — it rides along rather than holding rigidly.)
static func _escort_spec(rng: RandomNumberGenerator, entry: Dictionary, cell: Vector2i, max_row: int, sector_depth: int, level_index: int) -> WaveSpec:
	var w = _make_wave_spec(rng, entry, sector_depth, level_index, 0)
	w.count = 1
	w.lane = int(cell.x)
	w.spawn_y = -12.0 - float(max_row - int(cell.y)) * ESCORT_ROW_GAP
	w.spawn_delay = 0.0   # authored burst — whole convoy enters together; rows are SPATIAL
	w.movement_override = Roster.make_movement({"movement": "straight"})
	w.silent = true
	return w


# Clamp every speed-bearing spec to the SLOWEST member's move_speed so a mixed-speed formation
# advances in unison (mirrors authored_patterns._lock_to_slowest). Specs with no resolved speed
# (move_speed <= 0) are left alone and don't drag the minimum to zero.
static func _lock_specs_to_slowest(specs: Array) -> void:
	var slowest: float = INF
	for ws in specs:
		if ws.move_speed > 0.0:
			slowest = minf(slowest, ws.move_speed)
	if slowest == INF:
		return
	for ws in specs:
		if ws.move_speed > 0.0:
			ws.move_speed = slowest


# Pick a heavy for a beat (midpoint or coda). prefer_capital orders the two pools:
# the coda (node 2+) prefers 64px capitals; the midpoint always wants a 32px anchor.
# Falls back across classes, then to the generic RARE/tough pool (_pick_elite), so a
# beat never drops. Prefers an entry not already used this level.
static func _pick_heavy(rng: RandomNumberGenerator, sector_depth: int, level_index: int, exclude: Array, prefer_capital: bool) -> Dictionary:
	var order: Array = (["capital", "anchor"] if prefer_capital else ["anchor", "capital"])
	for cls in order:
		var pool: Array = Roster.heavies_eligible(cls, sector_depth, level_index)
		if pool.is_empty():
			continue
		var fresh: Array = []
		for e in pool:
			if not exclude.has(e):
				fresh.append(e)
		if not fresh.is_empty():
			pool = fresh
		return pool[rng.randi() % pool.size()]
	return _pick_elite(rng, sector_depth, level_index, exclude)


# Pick a heavy from the generic RARE/tough fallback pool (used when no heavy_class
# entry is unlocked at this coordinate). Prefers the depth-eligible RARE pool;
# failing that, tough/large UNCOMMONs. Prefers an unused entry. {} if none exist.
static func _pick_elite(rng: RandomNumberGenerator, sector_depth: int, level_index: int, exclude: Array) -> Dictionary:
	var pool: Array = Roster.entries_eligible(Roster.Tier.RARE, sector_depth, level_index)
	if pool.is_empty():
		for e in Roster.entries_eligible(Roster.Tier.UNCOMMON, sector_depth, level_index):
			var tags: Array = e.get("tags", [])
			var size: String = String(e.get("size", "medium"))
			if "tough" in tags or size == "large" or size == "huge":
				pool.append(e)
	if pool.is_empty():
		return {}
	var fresh: Array = []
	for e in pool:
		if not exclude.has(e):
			fresh.append(e)
	if not fresh.is_empty():
		pool = fresh
	return pool[rng.randi() % pool.size()]


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
static func _pick_pair(rng: RandomNumberGenerator, sector_depth: int, level_index: int, used: Array, avoid_movement: String = "") -> Array:
	var first: Dictionary = _pick_entry(rng, sector_depth, level_index, used, PackedStringArray(), Roster.Tier.RARE, avoid_movement)
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


# Boss level: a FULL 5-6 wave escalating run-up, THEN the boss (Roman 2026-06-27: was 2-4 — the boss
# should arrive after a substantial fight). This is the level's KITCHEN-SINK moment — each wave draws
# from the whole pool (varied), unlike a normal node's small palette. Lead-in chaff filters out
# enemies whose conflict_tags overlap the boss's own pressure signature. Each wave is floored to a
# dense, escalating count (boss lead-ins skip the budget pass, so without this a low-base elite would
# trickle). The final lead-in is thinned + re-bannered so the boss arrival reads cleanly.
static func _build_boss_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	var boss_entry: Dictionary = _pick_boss(rng, sector_depth)
	# The Zealot Battleship (Roman 2026-07-01) is a PERSISTENT boss spawned at level start by main.gd
	# and gated by the wave director — the level is just its ~5-6 boss-less enemy waves (one maneuver
	# between each). So we build the run-up waves but skip the final _make_boss_wave for it.
	var is_battleship: bool = String(boss_entry["scene"]).contains("boss_z_battleship")
	var conflict_tags: PackedStringArray = PackedStringArray(
		BOSS_LEADIN_CONFLICTS.get(boss_entry["scene"], []))
	var n_leadin: int = clampi(4 + sector_depth, 5, 6)  # S1=5, S2=6, deep=6 — a full run-up
	var used: Array = []
	var waves: Array = []
	for i in n_leadin:
		var entry: Dictionary = _pick_entry(rng, sector_depth, level_index + i, used, conflict_tags)
		used.append(entry)
		var w = _make_wave_spec(rng, entry, sector_depth, level_index + i, i, true)
		if i == n_leadin - 1 and not is_battleship:
			# Thin the final lead-in and re-banner so the boss arrival reads cleanly.
			w.count = maxi(2, int(w.count / 2))
			w.announce_text = "BOSS APPROACHING"
		else:
			# Escalating density floor so every run-up wave is a real wave, not a 1-2 trickle, and the
			# run-up visibly builds toward the boss. Chaff escalates harder (5→13); a non-chaff elite
			# wave escalates gently and is capped (elites are tough — a few is already a beat).
			var floor_n: int = (5 + i * 2) if bool(entry.get("chaff", false)) else mini(3 + i, 5)
			w.count = maxi(int(w.count), floor_n)
		waves.append(w)
	if not is_battleship:
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
	var bs = Weapon.new()
	bs.fire_pattern = Weapon.FirePattern.SPREAD
	bs.aim = Weapon.Aim.STRAIGHT_DOWN
	bs.bullet_scene = EnemyBullet
	bs.spread_count = 5
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
static func _pick_entry(rng: RandomNumberGenerator, sector_depth: int, level_index: int, exclude: Array, exclude_tags: PackedStringArray = PackedStringArray(), max_tier: int = Roster.Tier.RARE, avoid_movement: String = "") -> Dictionary:
	var tier := _roll_tier(rng, sector_depth, level_index)
	if tier > max_tier:
		tier = max_tier
	# DEPTH GATING (Roman 2026-05-31): pull only entries unlocked at this
	# progression coordinate. sector_depth here is WaveGen's 1-based sector
	# (maps to roster unlock_sector); level_index is the 0-based combat-node
	# index within the sector (maps to roster unlock_depth). entries_eligible
	# treats absent/0 thresholds as always-available, and the basic chaff are
	# unlock 0 so the COMMON pool is never empty at (sector 1, depth 0).
	var pool: Array = Roster.entries_eligible(tier, sector_depth, level_index)
	# Fall back to other tiers if the rolled tier has nothing unlocked yet.
	# Keep the depth filter on the fallback tiers so a gated enemy can't sneak
	# in via a tier-downgrade (e.g. an empty UNCOMMON pool must not pull a
	# locked RARE through an unfiltered COMMON list).
	if pool.is_empty() and Roster.Tier.UNCOMMON <= max_tier:
		pool = Roster.entries_eligible(Roster.Tier.UNCOMMON, sector_depth, level_index)
	if pool.is_empty():
		pool = Roster.entries_eligible(Roster.Tier.COMMON, sector_depth, level_index)
	# Last-ditch roster-misconfig guard: if even the filtered COMMON pool is
	# empty (should be impossible given the unlock-0 basic chaff), fall back to
	# the unfiltered COMMON tier so wave generation can never softlock.
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
	# Anti-repetition: avoid back-to-back same movement archetype (e.g. a run of
	# "fast_straight" dart+bomb_drone rushes). Prefer a different archetype; keep
	# the full pool if that's all that's available (small shallow pools).
	if avoid_movement != "":
		var varied: Array = []
		for e in pool:
			if str(e.get("movement", "")) != avoid_movement:
				varied.append(e)
		if not varied.is_empty():
			pool = varied
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
		# CHAFF-ONLY (Roman 2026-06-04): gate to `chaff:true` entries. The bump was
		# always meant for chaff; once frigate/gunship were pulled earlier for
		# heavy-beat variety, applying +50% to a base-3 heavy ballooned it into a
		# 6-ship wall. Heavies now keep their designed counts.
		if not is_boss_leadin and base > 1 and bool(entry.get("chaff", false)):
			count = int(ceil(float(count) * 1.5))
	# Per-sector chaff bonus (designer 2026-05-24 economy pass): COMMONs get
	# +1 enemy per sector beyond the first (S1=+0, S2=+1, S3=+2). UNCOMMON +
	# RARE get nothing extra here — they pick up difficulty via the per-wave
	# HP bonus below. Boss lead-ins are exempt; they're tuned by _build_boss_waves.
	var chaff_bonus: int = 0
	var roster_tier: int = int(entry.get("tier", Roster.Tier.COMMON))
	if roster_tier == Roster.Tier.COMMON and not is_boss_leadin:
		# Cross-sector chaff bonus (existing): +1 per sector past the first.
		chaff_bonus = maxi(sector_depth - 1, 0)
		# Chaos ramp (Roman 2026-06-01): deeper combat NODES within a sector pack
		# more chaff. +1 at the 2nd node (level_index 1), +1 per further node.
		chaff_bonus += mini(level_index, COMBAT_DEPTH_CHAFF_MAX)
		# Cap the COMBINED bonus so a deep-sector/deep-node COMMON wave can't
		# balloon (the two terms stack).
		chaff_bonus = mini(chaff_bonus, CHAFF_BONUS_TOTAL_CAP)
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
	# Fast-chaff WALL (construction §8): entries tagged `wall: true` (dart/bomb_drone)
	# arrive as a chunked, gap-shifting wall instead of a one-at-a-time spread trickle
	# that goes sparse and kills end-of-node momentum. Computed here, applied AFTER the
	# tandem/force rolls below so it isn't stomped (force_formation still wins). Only
	# affects SINGLE waves built here — mixed sub-waves keep their opposite-side spread
	# (halved counts there don't trickle). Boss lead-ins are exempt.
	var want_wall: bool = bool(entry.get("wall", false)) and not is_boss_leadin
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
	# NOTE (2026-05-31): the "" default only applies when the key is ABSENT.
	# Bespoke enemies (Burner, Firecore Drone, firecore_cruiser) set
	# `movement: null` explicitly, so .get returns null and String(null) is an
	# invalid constructor in Godot 4.6 — it crashed _make_wave_spec for any
	# null-movement enemy that rolled. Guard the null so mv_key is "" (→ not
	# tandem-eligible, which is correct; Burner's formation comes from the
	# unconditional _apply_force_formation below, not this 25% roll).
	var mv_raw: Variant = entry.get("movement", "")
	var mv_key: String = String(mv_raw) if mv_raw != null else ""
	var tandem_eligible: bool = mv_key in ["straight"]   # straight descenders pair into tandem rows
	if tandem_eligible and not want_wall and not is_boss_leadin and level_index >= 2 and rng.randf() < 0.25:
		w.formation = WaveSpec.Formation.TOP_TANDEM_PAIRS
		if (w.count % 2) == 1:
			w.count += 1
	# Per-entry forced formation (Burner: must always arrive in TOP_TANDEM_PAIRS
	# so each member finds a partner to beam with). Honored for single waves and
	# boss lead-ins here; the mixed-wave path re-applies it in _build_combat_waves
	# after that path stomps formation. force_even_count guarantees no lone
	# trailing member (a lone burner just descends + leaves, but pairs are intent).
	_apply_force_formation(w, entry)
	# WALL wins over the random spread + tandem roll, but force_formation (Burner's
	# tandem beam-pair) is explicit and takes precedence — apply WALL only when nothing
	# was force-set.
	if want_wall and not entry.has("force_formation"):
		w.formation = WaveSpec.Formation.WALL
	var sp: Resource = Roster.make_shoot(entry)
	if sp != null:
		w.shoot_pattern_override = sp
	# Components = pre-built "components" + dict-built "emitters" (droppers/spawners). Emitters add on top.
	w.components_override = Roster.make_components(entry) + Roster.make_emitters(entry)
	w.mounts_override = Roster.make_mounts(entry)
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
	# Locomotion (chassis stats); a random wave has no formation depth override, so the enemy's
	# roster-default depth (compose_stats depth_bp) rides depth_override.
	w.move_speed = float(stats.get("move_speed", 0.0))
	w.weight = float(stats.get("weight", 0.0))
	w.turn_rate = float(stats.get("turn_rate", 0.0))
	w.accel = float(stats.get("accel", 0.0))
	w.depth_override = float(stats.get("depth_bp", -1.0))
	return w


# Apply a roster entry's force_formation / force_even_count onto a WaveSpec.
# Idempotent — safe to call again after the mixed-wave path overwrites
# formation. Validates the index against the Formation enum so a bad roster
# value can't set a garbage formation.
static func _apply_force_formation(w: WaveSpec, entry: Dictionary) -> void:
	if not entry.has("force_formation"):
		return
	var ff: int = int(entry["force_formation"])
	if ff < 0 or ff > int(WaveSpec.Formation.PINCER):
		return
	w.formation = ff
	if bool(entry.get("force_even_count", false)) and (w.count % 2) == 1:
		w.count += 1


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
		return {"scene": "res://scenes/enemies/bosses/boss.tscn", "banner": "BOSS"}
	return BOSS_ROSTER[rng.randi() % BOSS_ROSTER.size()]


# Same inputs produce the same level. Lets the player retry from the same
# sector node without a different roll, and keeps testing reproducible.
static func _stable_seed(sector_depth: int, level_index: int, is_boss: bool) -> int:
	var s: int = sector_depth * 100003
	s += level_index * 7919
	s += 5 if is_boss else 0
	# Fold in the run seed so the SAME node rolls a different comp each patrol,
	# while staying reproducible WITHIN a run (a node retry is identical). See
	# wave_streaming spec §7.2 / bridge §5 (content deterministic per run+node).
	# Mixed with a large multiplier (not added) so even small/structured run seeds
	# produce well-separated RNG streams; run_seed 0 (tools) is a no-op.
	s ^= _run_seed() * 2654435761
	return s


# The current run's seed (0 if no run is active, e.g. in headless tool runs, so
# tools stay deterministic). Static-safe: reads the Run autoload via the tree.
static func _run_seed() -> int:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var run = (ml as SceneTree).root.get_node_or_null("Run")
		if run != null:
			var v = run.get("run_seed")
			if v != null:
				return int(v)
	return 0
