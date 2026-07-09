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
const EnemyBullet = preload("res://scenes/projectiles/projectile_ball.tscn")
const FormationShapesC = preload("res://scripts/levels/formation_shapes.gd")
const FormationComposer = preload("res://scripts/levels/formation_composer.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")

# Per-boss chaff conflict tags. Lead-in waves drop chaff carrying any of
# these tags so the boss's signature pressure doesn't overlap a chaff
# pattern that demands the same player attention budget. Empty / unlisted
# scene = no filtering.
# Chaos ramp (Roman 2026-06-01). Per-node chaff add caps at this; combined with
# the cross-sector term, the grand total chaff bonus caps at CHAFF_BONUS_TOTAL_CAP.
const COMBAT_DEPTH_CHAFF_MAX := 3
const CHAFF_BONUS_TOTAL_CAP := 4

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


# LEGACY, TOOL-ONLY (dead on the production 3-stretch path, 2026-07-02): the pre-3-stretch M5
# wave-count rule. Kept solely because tools/test_wave_count.gd still asserts it; not called by
# build(). Delete alongside that tool if it's ever retired.
static func _wave_count_for(sector_depth: int, level_index: int) -> int:
	return clampi(5 + level_index + (sector_depth - 1), 5, 8)


# LEGACY, TOOL-ONLY (dead on the production 3-stretch path, 2026-07-02): the pre-3-stretch M5
# level enemy budget (per-stretch STRETCH_BUDGET replaced it). Kept solely because
# tools/test_budget.gd still reports against it; not called by build().
static func _level_budget(sector_depth: int, level_index: int) -> int:
	return clampi(int(round(140.0 + 25.0 * level_index + 35.0 * (sector_depth - 1))), 140, 350)


# Streaming density cap — now a SLOT cap (level_structure_redesign_2026-07-01): the ceiling on
# summed enemy FOOTPRINTS on screen (director._alive_slots), not a headcount. A wall of small chaff
# (1 slot) packs to the cap; a few cruisers (9-12 slots) fill it. This is the LEVEL default / opener
# value; step 2 (3-stretch loop) ramps it per stretch (16 → 26 → 36). Hazards set their own cap
# (their bodies weigh 1, so it stays a headcount). The director consumes this via main.gd.
static func cap_for(sector_depth: int, level_index: int) -> int:
	return clampi(26 + 2 * level_index + 2 * (sector_depth - 1), 26, 36)


# Scale the CHAFF waves so their total approaches `target`, leaving discrete beats (heavies / capped
# flocks / accents) at their authored counts. `chaff_flags` is parallel to `waves` — true = scalable
# chaff. Called PER STRETCH (level_structure_redesign_2026-07-01) with the stretch budget. (Roman
# 2026-06-27: was keyed on base_count >= 4, which MISCLASSIFIED low-base uncommon chaff as elite and
# left it to trickle at count 2-3. The explicit flag scales it densely.)
static func _apply_budget(waves: Array, chaff_flags: Array, target: int) -> void:
	if waves.is_empty():
		return
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


# 3-STRETCH LEVEL (level_structure_redesign_2026-07-01). A combat level is three ~1-minute pieces:
#   OPENER    — mid chaff, slot cap 16.
#   OBSTACLES — tankier / elites, slot cap 26.
#   CLIMAX    — densest (elite pack / mini-boss; the boss on boss nodes), slot cap 36.
# Each stretch is a run of START/MIDDLE/END sub-wave UNITS (the palette/formation/accent vocabulary);
# its FIRST sub-wave opens a ScoreWave (banner "WAVE n/3" + the stretch's slot cap), the rest silent.
# Chaff scales to STRETCH_BUDGET per stretch; recycling holds the screen so ~300 enemies fill ~3 min.
const STRETCH_COUNT: int = 3
const STRETCH_SLOT_CAPS: Array = [16, 26, 36]   # density ramp; applied via WaveSpec.slot_cap on entry
const STRETCH_UNITS: Array = [4, 4, 4]          # START/MIDDLE/END sub-wave units per stretch
const STRETCH_BUDGET: int = 100                 # enemies per stretch (chaff scaled to hit this)
# Deliberate 1-2s beat between sub-wave units within a stretch (pacing; see WaveSpec.lead_pause).
const SUBWAVE_PAUSE_MIN: float = 1.0
const SUBWAVE_PAUSE_MAX: float = 2.0
# Combat chaff roll-back: how many times a MISSED chaff flies back + re-enters before it finally
# leaves (level_structure_redesign_2026-07-01). >0 makes ~300 enemies fill ~3 min (kill-gated) instead
# of leaking off in ~60s; capped so a perpetually-dodged straggler still eventually bows out. 0 =
# the old leak-off behavior. REVERSES the roster's recycle:0 for high-count chaff (Roman 2026-06-08).
const CHAFF_RECYCLE_PASSES: int = 2

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
# screen convoy into a mid wave. Discrete spectacle, lockstep-clamped to the slow core. Row pre-stack
# uses the shared formation_shapes.prestack_y (one ROW_GAP for all formation sites). Tune CHANCE freely.
const ESCORT_CHANCE: float = 0.4

# ============================================================================
# SHOOTER-DENSITY DIFFICULTY RAMP (Roman playtest 2026-07-06)
# ----------------------------------------------------------------------------
# "Enemies capable of shooting make the game much harder — use them more sparingly
#  early, in smaller numbers, ramping across difficulty." An ARMED entry is any that
#  projects a threat (Roster.entry_is_armed: a shoot slot, a firing mount, or an
#  active dropper). Two independent levers, both keyed on the CHAFF layer only —
#  heavies/capstones/mini-bosses stay armed (they're the discrete, telegraphed
#  threats the ramp is NOT trying to soften). Generic over the armed flag; zero
#  per-enemy special-casing.
#
# LEVER 1 — ARMED CHAFF-TYPE CAP (palette composition, _pick_palette/_extend_palette):
#   How many DISTINCT armed chaff types the level's palette may carry, indexed by
#   eff_depth (= level_index + stretch; opener of the first node = 0). Below the table
#   length the value at [eff_depth] applies; at/after it, unbounded (-1). The opener
#   leans fully unarmed; deep levels are unconstrained. Graceful floor: if the
#   faction-filtered chaff pool has ONLY armed entries, we still fill the palette from
#   them (never returns empty) — the cap governs preference, not availability.
const ARMED_CHAFF_TYPE_CAP := [0, 1, 1, 2, 2, 3]   # eff_depth 0,1,2,3,4,5+; -1 past the end = uncapped
const ARMED_CHAFF_TYPE_CAP_DEEP := -1              # value used once eff_depth >= table length (uncapped)

# LEVER 2 — ARMED CHAFF COUNT DAMP (_make_wave_spec): when an armed chaff wave is built
#   at a SHALLOW effective depth, scale its count down so armed shooters arrive in small
#   clusters early instead of full walls. Unarmed chaff is untouched (harmless volume).
#   Applies only while eff_depth < ARMED_DAMP_DEPTH; the factor lerps from
#   ARMED_DAMP_FACTOR_MIN (eff_depth 0) up to 1.0 (at the threshold), floored so a wave
#   never drops below ARMED_DAMP_FLOOR shooters. Heavies (chaff:false) are exempt.
const ARMED_DAMP_DEPTH := 3            # eff_depth at/after which no damp is applied
const ARMED_DAMP_FACTOR_MIN := 0.4     # multiplier at eff_depth 0 (ramps to 1.0 by ARMED_DAMP_DEPTH)
const ARMED_DAMP_FLOOR := 2            # never damp an armed chaff wave below this many


# The armed-chaff-type cap for a given effective depth (LEVER 1). -1 = uncapped.
static func _armed_chaff_cap(eff_depth: int) -> int:
	if eff_depth < 0:
		eff_depth = 0
	if eff_depth < ARMED_CHAFF_TYPE_CAP.size():
		return int(ARMED_CHAFF_TYPE_CAP[eff_depth])
	return ARMED_CHAFF_TYPE_CAP_DEEP


# The armed-chaff count multiplier for a given effective depth (LEVER 2). 1.0 once past
# the ramp; lerps up from ARMED_DAMP_FACTOR_MIN at depth 0.
static func _armed_damp_factor(eff_depth: int) -> float:
	if eff_depth >= ARMED_DAMP_DEPTH or ARMED_DAMP_DEPTH <= 0:
		return 1.0
	var t: float = float(maxi(eff_depth, 0)) / float(ARMED_DAMP_DEPTH)
	return lerpf(ARMED_DAMP_FACTOR_MIN, 1.0, t)


# Assemble a chaff palette from an ALREADY-SHUFFLED pool while respecting the armed-type
# cap (LEVER 1). Deterministic: walks the pool in its (seeded-shuffled) order, taking
# unarmed entries freely and armed entries only until the cap is reached — then it makes
# a SECOND pass to backfill remaining slots from the armed leftovers (graceful fallback
# so a pool with few/zero unarmed entries still fills n_want without an extra RNG draw,
# preserving stream determinism). `already` seeds the dedup (used when extending).
static func _fill_chaff_capped(pool: Array, n_want: int, armed_cap: int, already: Array = []) -> Array:
	var chosen: Array = already.duplicate()
	var armed_taken: int = 0
	for e in already:
		if Roster.entry_is_armed(e):
			armed_taken += 1
	var deferred_armed: Array = []
	# Pass 1: prefer unarmed; take armed only under the cap.
	for e in pool:
		if chosen.size() >= n_want:
			break
		if chosen.has(e):
			continue
		if Roster.entry_is_armed(e):
			if armed_cap >= 0 and armed_taken >= armed_cap:
				deferred_armed.append(e)   # over cap for now — remember for backfill
				continue
			armed_taken += 1
		chosen.append(e)
	# Pass 2: backfill from the deferred armed leftovers (only if we still need types and
	# the unarmed supply ran dry). Keeps the palette full rather than starving it.
	for e in deferred_armed:
		if chosen.size() >= n_want:
			break
		if not chosen.has(e):
			chosen.append(e)
	return chosen


static func _build_combat_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	# LevelMotif (conductor review §5, roadmap P2.7). Two things are now rolled ONCE per level and
	# threaded through the three stretches instead of re-rolled per stretch:
	#   1. The PALETTE (hoisted): the level's base chaff set + heavy, rolled at the opener depth. Each
	#      stretch EXTENDS it (adds one deeper chaff entry via the eff_depth mechanism) so the three
	#      stretches share a coherent enemy identity that GROWS, rather than three disjoint rolls.
	#   2. The MOTIF: a signature grammar primitive + movement key + three pre-composed escalating
	#      formation variants (v1 bare / v2 grown / v3 full density). Each stretch's END capstone draws
	#      escalation[stretch] so the player watches ONE formation idea build across the level.
	var base_palette: Dictionary = _pick_palette(rng, sector_depth, level_index)
	var motif: Dictionary = _roll_motif(rng, base_palette, level_index)
	var waves: Array = []
	for s in STRETCH_COUNT:
		waves.append_array(_build_stretch(rng, sector_depth, level_index, s, base_palette, motif))
	# Stash the pre-composed capstone patterns onto Run meta so the producer chokepoint (main.gd, after
	# the adapter lift + authored auto-mix) can splice them as native authored phrases — the only
	# post-adapter authored-splice point on the production LevelData path. Keyed by stretch index; the
	# score-side splice matches ScoreWave order 1:1 with the stretches. (Falls back to the in-line random
	# shape_override capstone below if a variant failed to compose.)
	_stash_motif(motif)
	return waves


# Build one stretch's sub-waves. Escalates by stretch index: a deeper "effective depth" pulls tougher
# palette chaff + heavier capstones, and the stretch carries slot cap 16/26/36. The FIRST sub-wave
# opens the stretch's ScoreWave (banner + slot cap); the rest are silent. Chaff scaled to STRETCH_BUDGET.
static func _build_stretch(rng: RandomNumberGenerator, sector_depth: int, level_index: int, stretch: int, base_palette: Dictionary, motif: Dictionary) -> Array:
	# Deeper stretches read as "further in" for tier/palette (opener light → climax elite).
	var eff_depth: int = level_index + stretch
	# PALETTE (hoisted, review §5): the level's base palette EXTENDED by one deeper chaff entry per
	# stretch (via eff_depth), not re-rolled — so the level's enemy identity grows instead of the three
	# stretches being disjoint. The heavy is the level's heavy (base_palette), deepened only if empty.
	var palette: Dictionary = _extend_palette(rng, base_palette, sector_depth, eff_depth, stretch)
	var chaff_types: Array = palette["chaff"]
	var heavy_type: Dictionary = palette["heavy"]
	if chaff_types.is_empty():
		return []   # roster misconfig guard (basic chaff is unlock 0, so this shouldn't happen)
	var slot_cap: int = int(STRETCH_SLOT_CAPS[stretch]) if stretch < STRETCH_SLOT_CAPS.size() else 26
	var is_climax: bool = (stretch == STRETCH_COUNT - 1)
	var n_units: int = int(STRETCH_UNITS[stretch]) if stretch < STRETCH_UNITS.size() else 2
	var waves: Array = []
	# Parallel to `waves`: true = scalable chaff, false = a DISCRETE beat (heavy / flock / accent).
	var chaff_flags: Array = []
	var opened: bool = false
	for u in n_units:
		var lead_lr: bool = (u % 2 == 0)
		var is_last_unit: bool = (u == n_units - 1)
		# START — palette chaff sweep. The stretch's first sub-wave opens the ScoreWave (banner + the
		# stretch's slot cap); every later sub-wave is silent (attaches to the stretch).
		var e_start: Dictionary = chaff_types[u % chaff_types.size()]
		var s_start = _make_wave_spec(rng, e_start, sector_depth, eff_depth, u)
		s_start.formation = WaveSpec.Formation.TOP_LEFT_TO_RIGHT if lead_lr else WaveSpec.Formation.TOP_RIGHT_TO_LEFT
		s_start.spawn_delay = 0.5
		if not opened:
			s_start.silent = false
			s_start.announce_text = ""      # default "WAVE n / 3"
			s_start.slot_cap = slot_cap     # apply this stretch's density on entry
			opened = true
		else:
			s_start.silent = true
			# A deliberate 1-2s reposition beat between sub-wave units (not before the stretch opener).
			s_start.lead_pause = rng.randf_range(SUBWAVE_PAUSE_MIN, SUBWAVE_PAUSE_MAX)
		_apply_force_formation(s_start, e_start)
		waves.append(s_start); chaff_flags.append(true)
		# MIDDLE — the bulk; a different palette chaff, opposite sweep.
		var e_mid: Dictionary = chaff_types[(u + 1) % chaff_types.size()]
		var s_mid = _make_wave_spec(rng, e_mid, sector_depth, eff_depth, u)
		s_mid.formation = WaveSpec.Formation.TOP_RIGHT_TO_LEFT if lead_lr else WaveSpec.Formation.TOP_LEFT_TO_RIGHT
		s_mid.silent = true
		s_mid.spawn_delay = 0.35
		_apply_force_formation(s_mid, e_mid)
		waves.append(s_mid); chaff_flags.append(true)
		# END — capstone. Heavy on the OBSTACLES/CLIMAX stretches (always on the stretch's last unit,
		# ~60% otherwise); the opener leans lighter (flock/wall). Climax capstones run a touch bigger.
		var want_heavy: bool = (stretch >= 1) and (is_last_unit or rng.randf() < 0.6)
		if want_heavy and not heavy_type.is_empty():
			var s_end = _make_wave_spec(rng, heavy_type, sector_depth, eff_depth, u)
			var hi: int = 3 if is_climax else 2
			var lo: int = 1 if String(heavy_type.get("size", "")) in ["large", "huge"] else 2
			s_end.count = clampi(int(s_end.count), lo, hi)
			s_end.formation = WaveSpec.Formation.TOP_CENTER_OUT
			s_end.silent = true
			s_end.spawn_delay = 0.35
			waves.append(s_end); chaff_flags.append(false)   # discrete anchor
		else:
			var e_end: Dictionary = chaff_types[rng.randi() % chaff_types.size()]
			var s_end2 = _make_wave_spec(rng, e_end, sector_depth, eff_depth, u)
			s_end2.silent = true
			s_end2.spawn_delay = 0.35
			# When the MOTIF has a composed variant for THIS stretch, its authored phrase is spliced onto
			# this stretch's ScoreWave (main.gd, post-adapter) as the held-formation capstone — so on the
			# LAST unit we suppress the RANDOM geometric flock (it would double up on the signature burst)
			# and fall through to a plain chaff WALL/PINCER for texture. Non-last units + the fallback
			# (no motif variant composed) keep the classic random geometric capstone. Draw the RNG
			# unconditionally so suppression doesn't desync the seeded stream (a retry reproduces the level).
			var geo_roll: bool = rng.randf() < GEOMETRIC_CAPSTONE_CHANCE
			var motif_covers: bool = is_last_unit and _motif_has_variant(motif, stretch)
			if not e_end.has("force_formation") and geo_roll and not motif_covers:
				s_end2.shape_override = FormationShapesC.SHAPES[rng.randi() % FormationShapesC.SHAPES.size()]
				s_end2.count = clampi(int(s_end2.count), GEOMETRIC_FLOCK_MIN, GEOMETRIC_FLOCK_MAX)
				s_end2.movement_override = Roster.make_movement({"movement": "straight"})
				waves.append(s_end2); chaff_flags.append(false)   # discrete capped flock
			else:
				s_end2.formation = WaveSpec.Formation.WALL if lead_lr else WaveSpec.Formation.PINCER
				_apply_force_formation(s_end2, e_end)
				waves.append(s_end2); chaff_flags.append(true)    # scaled chaff wall
		# ACCENT — a crossing sting on the tail of non-last units.
		if not is_last_unit and rng.randf() < ACCENT_CHANCE:
			var s_acc = _make_accent_wave(rng, chaff_types[rng.randi() % chaff_types.size()], sector_depth, eff_depth, u)
			if s_acc != null:
				waves.append(s_acc); chaff_flags.append(false)   # discrete sting
	# CLIMAX finale: a mini-boss (if registered) or an elite pack, after the chaff wall.
	if is_climax:
		_append_climax_finale(rng, sector_depth, eff_depth, waves, chaff_flags)
	_apply_budget(waves, chaff_flags, STRETCH_BUDGET)
	return waves


# Mini-boss registry (level_structure_redesign_2026-07-01; populated 2026-07-02, review P2.8). A
# regular-node CLIMAX features a mini-boss when one is registered for the depth/faction, else an
# ELITE PACK. Entries: {scene, min_depth (vs eff_depth = level_index + 2 at the climax), faction
# (-1 = any), movement (optional key — overrides the roster movement so a straight-descent capital
# LOITERS through its climax instead of leaving in ~5s)}. Roster-known scenes compose through
# _make_wave_spec so they keep their mounts/stats (a bare scene load leaves roster-mounted capitals
# UNARMED — see _append_climax_finale). (Boss NODES use _build_boss_waves + the real boss, not this.)
const MINIBOSS_ROSTER: Array = [
	# Multi-part cruiser: tanky core + 4 shootable DestructiblePart sections — the one enemy already
	# built like a mini-boss. Universal home tag → legal for every faction (covers privateer, which
	# has no capital of its own). Placeholder art as of 2026-07-02.
	{"scene": "res://scenes/enemies/core/enemy_cruiser.tscn", "min_depth": 2, "faction": -1},
	# Hive drone carrier: self-escorting (streams beelining flechettes) — single-spawn is the point.
	# NOTE 16 HP reads soft for a 36-slot climax anchor; playtest may want a bump (script hard-set).
	{"scene": "res://scenes/enemies/factions/corporate/enemy_c_l_hive.tscn", "min_depth": 3, "faction": 2},
	# Zealot depth ladder: Helix (32 HP, single tank turret) anchors shallow climaxes, Crusader
	# (60 HP, 4 turrets + twin lasers + firecore death drop) the deep ones. Both are roster-mounted →
	# MUST compose (unarmed bare); both descend straight at recycle 0 → loiter override keeps them
	# on-screen for the fight instead of exiting in ~5s.
	{"scene": "res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn", "min_depth": 2, "faction": 3, "movement": "loiter"},
	{"scene": "res://scenes/enemies/factions/zealot/enemy_z_l_crusader.tscn", "min_depth": 4, "faction": 3, "movement": "loiter"},
	# Considered + deferred: Tyrant broadside frigate (supremacy) — scene bakes 6 HP and its script
	# header still says retired; needs a bench pass before it anchors a climax (review 2026-07-02).
]


static func _pick_miniboss(rng: RandomNumberGenerator, eff_depth: int, faction: int) -> Dictionary:
	var pool: Array = []
	for m in MINIBOSS_ROSTER:
		if eff_depth < int(m.get("min_depth", 0)):
			continue
		var mf: int = int(m.get("faction", -1))
		if mf < 0 or mf == faction:
			pool.append(m)
	if pool.is_empty():
		return {}
	return pool[rng.randi() % pool.size()]


# Append the CLIMAX finale onto `waves`: a mini-boss (registered) or an elite pack — 2-3 heavy TYPES,
# a small cluster of each, arriving centre-out after a beat. Discrete (chaff_flags false) so the chaff
# budget flows around it. This is the level's peak threat at the 36-slot cap.
static func _append_climax_finale(rng: RandomNumberGenerator, sector_depth: int, eff_depth: int, waves: Array, chaff_flags: Array) -> void:
	var mb: Dictionary = _pick_miniboss(rng, eff_depth, Roster.get_faction_filter())
	if not mb.is_empty():
		# Roster-known scenes COMPOSE through _make_wave_spec (review P2.8, 2026-07-02): a bare
		# WaveSpec skips the roster's mounts/stats overlay, so roster-mounted capitals (Crusader,
		# Helix) would arrive UNARMED. Composing inherits weapons, tuned HP/bounty, and locomotion;
		# the finale then stamps its own count/formation/pause on top. A non-roster scene keeps the
		# bare-load path — it must then be fully self-sufficient on disk (script-fallback stats + guns).
		var entry: Dictionary = Roster.entry_for_scene(String(mb.get("scene", "")))
		var wm: WaveSpec
		if not entry.is_empty():
			wm = _make_wave_spec(rng, entry, sector_depth, eff_depth, 0)
		else:
			wm = WaveSpec.new()
			wm.enemy_scene = load(String(mb.get("scene", "")))
		if wm.enemy_scene != null:
			wm.count = 1
			wm.formation = WaveSpec.Formation.TOP_CENTER_OUT
			wm.silent = true
			wm.lead_pause = 1.5   # a beat before the mini-boss arrives
			# Optional registry movement override (e.g. "loiter") so a straight-descent capital
			# holds the field for the fight instead of exiting with its recycle-0 descent.
			var mv: String = String(mb.get("movement", ""))
			if mv != "":
				wm.movement_override = Roster.make_movement({"movement": mv})
			waves.append(wm); chaff_flags.append(false)
			return
	# Elite pack fallback: 2-3 distinct heavies, a couple of each, centre-out.
	var used: Array = []
	var n_types: int = 2 + (rng.randi() % 2)   # 2-3 elite types
	for k in n_types:
		var e: Dictionary = _pick_heavy(rng, sector_depth, eff_depth, used, k == 0)   # first prefers a capital
		if e.is_empty():
			break
		used.append(e)
		var w = _make_wave_spec(rng, e, sector_depth, eff_depth, k)
		w.count = clampi(int(w.count), 2, 3)
		w.formation = WaveSpec.Formation.TOP_CENTER_OUT
		w.silent = true
		if k == 0:
			w.lead_pause = 1.5   # a beat before the pack crashes in
		waves.append(w); chaff_flags.append(false)


# PER-LEVEL unit PALETTE (Roman 2026-06-27; HOISTED to true per-level 2026-07-02, review §5): a small
# subset of the eligible roster the whole level draws from. {"chaff": Array of chaff-tagged entries,
# "heavy": one heavy entry ({} if none unlocked)}. Rolled ONCE per level in _build_combat_waves at the
# OPENER depth (level_index); each stretch EXTENDS this base via _extend_palette (adds one deeper chaff
# entry) rather than re-rolling, so the level's enemy identity is coherent and grows across the three
# stretches instead of three disjoint rolls. Chaff count grows with depth (2 at the opener → 3 deep).
# Force-formation chaff (Burner etc.) is excluded — it needs its own beat.
static func _pick_palette(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Dictionary:
	var chaff_pool: Array = []
	for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON]:
		for e in Roster.entries_eligible(tier, sector_depth, level_index):
			if bool(e.get("chaff", false)) and not e.has("force_formation"):
				chaff_pool.append(e)
	FormationShapesC.fisher_yates(chaff_pool, rng)
	# 2 chaff types at the opener (avoids a whole level of ONE unit), up to 3 deep — a tight subset.
	# Kitchen-sink (the full pool) is the boss lead-in's job, not a normal node's.
	var n_chaff: int = clampi(2 + level_index, 2, 3)
	# SHOOTER-DENSITY RAMP LEVER 1: cap how many ARMED chaff types the palette carries at this depth
	# (the base palette rolls at the opener depth = level_index). Prefers unarmed early; backfills from
	# armed leftovers if the pool lacks enough unarmed types so the palette never starves.
	var chaff: Array = _fill_chaff_capped(chaff_pool, n_chaff, _armed_chaff_cap(level_index))
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


# EXTEND the hoisted per-level palette for `stretch` (review §5): keep the level's base chaff + heavy,
# and (stretch 1+) append ONE deeper chaff entry drawn at eff_depth so the palette GROWS across the
# level without re-rolling. The added entry is deduped against the base. If the base has no heavy but a
# deeper heavy has since unlocked, adopt it. Returns a fresh dict (base is not mutated).
static func _extend_palette(rng: RandomNumberGenerator, base: Dictionary, sector_depth: int, eff_depth: int, stretch: int) -> Dictionary:
	var chaff: Array = (base.get("chaff", []) as Array).duplicate()
	var heavy: Dictionary = base.get("heavy", {})
	if stretch >= 1:
		# One deeper chaff entry from the eff_depth-eligible pool, not already in the palette.
		var deep_pool: Array = []
		for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON]:
			for e in Roster.entries_eligible(tier, sector_depth, eff_depth):
				if bool(e.get("chaff", false)) and not e.has("force_formation") and not chaff.has(e):
					deep_pool.append(e)
		if not deep_pool.is_empty():
			# SHOOTER-DENSITY RAMP LEVER 1: the added deep entry must respect this stretch's armed-type
			# cap. If the palette already holds its armed quota, prefer an UNARMED deep entry; only fall
			# back to an armed one when no unarmed deep entry exists (graceful — the palette still grows).
			# Draw the index unconditionally FIRST so the seeded stream stays reproducible regardless of
			# which candidate we ultimately accept, then re-home it into the preferred sub-pool.
			var pick_idx: int = rng.randi()
			var armed_now: int = 0
			for e in chaff:
				if Roster.entry_is_armed(e):
					armed_now += 1
			var cap: int = _armed_chaff_cap(eff_depth)
			var over_cap: bool = (cap >= 0 and armed_now >= cap)
			var candidates: Array = deep_pool
			if over_cap:
				var unarmed_deep: Array = deep_pool.filter(func(e): return not Roster.entry_is_armed(e))
				if not unarmed_deep.is_empty():
					candidates = unarmed_deep   # honor the cap; else keep the full pool (grow anyway)
			chaff.append(candidates[pick_idx % candidates.size()])
	# Adopt a deeper heavy only if the level had none.
	if heavy.is_empty():
		heavy = _pick_heavy(rng, sector_depth, eff_depth, [], eff_depth >= 1 or sector_depth >= 2)
	return {"chaff": chaff, "heavy": heavy}


# LevelMotif (review §5, roadmap P2.7). Roll the level's recurring formation identity ONCE and
# pre-compose THREE escalating variants of it (one per stretch), all seeded from `rng` (the content
# stream) so a node retry reproduces the whole thing. Returns:
#   {"primitive", "movement", "variants":[v1,v2,v3], "family"}
# where each variant is an AuthoredPatterns-schema pattern dict (from FormationComposer) sized to fit
# that stretch's slot-cap share, or {} if composition failed (the in-line random capstone is the
# fallback for that stretch). Escalation: v1 bare primitive (small N, fits the opener's 0.6 share of
# cap 16), v2 + ECHO/THICKEN/ZONE_ASSIGN (obstacles, cap 26), v3 + LEAD/CORE_SCREEN at full density
# (climax, cap 36).
static func _roll_motif(rng: RandomNumberGenerator, palette: Dictionary, level_index: int) -> Dictionary:
	# Signature MOVEMENT key: pick one that's actually present among the palette chaff's eligible keys
	# (intersect palette eligibility with the composer's known key vocabulary) so the motif reads with
	# the units the level actually fields. Falls back to "straight" if the intersection is empty.
	var key_pool: Array = _palette_movement_keys(palette)
	var mv: String = key_pool[rng.randi() % key_pool.size()] if not key_pool.is_empty() else "straight"
	# Signature PRIMITIVE. Fast keys favor shallow directional shapes (SLASH/WEDGE/PICKET); slow keys
	# favor holding shapes (PICKET/FILE/PILLAR/CORRIDOR). CORE_SCREEN/CROSS_PAIR reserved for the v3
	# LEAD/escort escalation, not the base signature.
	var prim: String
	if FormationComposer.is_fast_key(mv):
		prim = [FormationComposer.PRIM_SLASH, FormationComposer.PRIM_WEDGE, FormationComposer.PRIM_PICKET][rng.randi() % 3]
	else:
		prim = [FormationComposer.PRIM_PICKET, FormationComposer.PRIM_FILE, FormationComposer.PRIM_PILLAR, FormationComposer.PRIM_CORRIDOR][rng.randi() % 4]

	# Per-stretch member budgets: the composed capstone is a DISCRETE burst, held to a share of the
	# stretch slot cap (v1 must fit the opener's 0.6 × 16 ≈ 9; v2 ~15; v3 ~24 at cap 36).
	var budgets: Array = [
		int(round(float(STRETCH_SLOT_CAPS[0]) * 0.6)),   # ~9
		int(round(float(STRETCH_SLOT_CAPS[1]) * 0.6)),   # ~15
		int(round(float(STRETCH_SLOT_CAPS[2]) * 0.66)),  # ~24
	]
	# Modifier ladders per tier. MIRROR is default-on for symmetry (slashes emit L/R pairs anyway).
	var v1_flags: Dictionary = {FormationComposer.MOD_MIRROR: true}
	# v2: grow — one of ECHO / THICKEN / ZONE_ASSIGN (seeded).
	var v2_flags: Dictionary = {FormationComposer.MOD_MIRROR: true}
	match rng.randi() % 3:
		0: v2_flags[FormationComposer.MOD_ECHO] = true
		1: v2_flags[FormationComposer.MOD_THICKEN] = true
		_: v2_flags[FormationComposer.MOD_ZONE_ASSIGN] = true
	# v3: full density — LEAD (leader tip + lockstep) or CORE_SCREEN, plus DEPTH_BAND for readability.
	var v3_flags: Dictionary = {FormationComposer.MOD_MIRROR: true, FormationComposer.MOD_DEPTH_BAND: true}
	var v3_prim: String = prim
	if rng.randf() < 0.5:
		v3_prim = FormationComposer.PRIM_CORE_SCREEN   # escort escalation (interior mediums)
	else:
		v3_flags[FormationComposer.MOD_LEAD] = true
		v3_flags[FormationComposer.MOD_THICKEN] = true
	var variants: Array = [
		FormationComposer.compose(prim, mv, 0, int(budgets[0]), v1_flags, rng, "motif_v1"),
		FormationComposer.compose(prim, mv, 1, int(budgets[1]), v2_flags, rng, "motif_v2"),
		FormationComposer.compose(v3_prim, mv, 2, int(budgets[2]), v3_flags, rng, "motif_v3"),
	]
	return {"primitive": prim, "movement": mv, "variants": variants}


# The set of composer movement keys reachable by this palette's chaff — the union of each chaff entry's
# pattern-eligibility keys, intersected with the composer's known key vocabulary (fast + slow). Lets the
# motif pick a signature key the level's units can actually express (review §5 "intersect with
# pattern_eligibility"). Empty ⇒ caller falls back to "straight".
static func _palette_movement_keys(palette: Dictionary) -> Array:
	# FIX 3 (2026-07-06): restrict the motif signature-key pool to LANE-PRESERVING keys only. The
	# motif signature drives formation-fill movement; a lane-abandoning key (side_traverse crosser,
	# lane_cut/hunt) made composed/motif formations ride across the top band and overrun their lanes.
	# The excluded keys stay available for accents / authored library patterns elsewhere.
	var out: Array = []
	for e in palette.get("chaff", []):
		var scene: String = String(e.get("scene", ""))
		for k in PatternEligibility.eligible_for(scene):
			var key: String = String(k)
			if FormationComposer.is_lane_preserving(key) and not out.has(key):
				out.append(key)
	return out


# True if the motif has a successfully-composed (non-empty, validating) variant for `stretch`.
static func _motif_has_variant(motif: Dictionary, stretch: int) -> bool:
	var variants: Array = motif.get("variants", [])
	if stretch < 0 or stretch >= variants.size():
		return false
	var v: Dictionary = variants[stretch]
	return not v.is_empty() and not (v.get("placements", []) as Array).is_empty()


# Stash the rolled motif onto Run meta so the producer chokepoint (main.gd) can splice the composed
# capstone variants as native authored phrases post-adapter, and can pass the motif's signature key +
# primitive as a HINT to AuthoredPatterns.maybe_inject (so injected picks reinforce the motif). Keyed
# per (sd,li) is unnecessary — the build is synchronous and consumed immediately by main.gd for THIS
# level. Headless/tool runs with no Run node simply skip the splice (the in-line capstones stand).
static func _stash_motif(motif: Dictionary) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var run = (ml as SceneTree).root.get_node_or_null("Run")
	if run == null:
		return
	run.set_meta("level_motif", motif)


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
	# instead of outrunning it (the audit's #1, finally load-bearing now that a generated formation is
	# mixed-speed). Shared impl: formation_shapes.lock_to_slowest (dedup, conductor review §3).
	FormationShapesC.lock_to_slowest(specs)
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
	# Row-0-leads pre-stack (formation_shapes.leads_from_zero): escort() cells use row-0-leads
	# (forward shield row 0 faces the player, rear guard trails) — so the forward screen enters
	# FIRST. Feeding cell.y into prestack_y (max_row-leads) inverted it (core/rear led). FIX 4.
	w.spawn_y = FormationShapesC.leads_from_zero(int(cell.y), max_row)
	w.spawn_delay = 0.0   # authored burst — whole convoy enters together; rows are SPATIAL
	w.movement_override = Roster.make_movement({"movement": "straight"})
	w.silent = true
	return w


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


# Boss level: a FULL 5-6 wave escalating run-up, THEN the boss (Roman 2026-06-27: was 2-4 — the boss
# should arrive after a substantial fight). This is the level's KITCHEN-SINK moment — each wave draws
# from the whole pool (varied), unlike a normal node's small palette. Lead-in chaff filters out
# enemies whose conflict_tags overlap the boss's own pressure signature. Each wave is floored to a
# dense, escalating count (boss lead-ins skip the budget pass, so without this a low-base elite would
# trickle). The final lead-in is thinned + re-bannered so the boss arrival reads cleanly.
static func _build_boss_waves(rng: RandomNumberGenerator, sector_depth: int, level_index: int) -> Array:
	var boss_entry: Dictionary = _pick_boss(rng, sector_depth)
	# PERSISTENT director-gated bosses (the Zealot Battleship + the Corporate Director) are spawned at
	# level start by main.gd and gated by the wave director — the level is just their ~5-6 boss-less enemy
	# waves (one maneuver between each). So we build the run-up waves but skip the final _make_boss_wave.
	var scene_s: String = String(boss_entry["scene"])
	var is_persistent_boss: bool = scene_s.contains("boss_z_battleship") or scene_s.contains("boss_c_director")
	var conflict_tags: PackedStringArray = PackedStringArray(
		BOSS_LEADIN_CONFLICTS.get(boss_entry["scene"], []))
	var n_leadin: int = clampi(4 + sector_depth, 5, 6)  # S1=5, S2=6, deep=6 — a full run-up
	var used: Array = []
	var waves: Array = []
	for i in n_leadin:
		var entry: Dictionary = _pick_entry(rng, sector_depth, level_index + i, used, conflict_tags)
		used.append(entry)
		var w = _make_wave_spec(rng, entry, sector_depth, level_index + i, i, true)
		if i == n_leadin - 1 and not is_persistent_boss:
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
	if not is_persistent_boss:
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
	# SHOOTER-DENSITY RAMP LEVER 2: damp ARMED CHAFF counts at shallow depth so shooters arrive in
	# small clusters early (unarmed chaff — the harmless volume — is untouched). `level_index` here is
	# the stretch's eff_depth on the combat path. Boss lead-ins keep their own tuning. Heavies (chaff
	# false) are exempt: they're the discrete telegraphed threats the ramp deliberately preserves.
	if not is_boss_leadin and bool(entry.get("chaff", false)) and Roster.entry_is_armed(entry):
		var damp: float = _armed_damp_factor(level_index)
		if damp < 1.0:
			# Floor at ARMED_DAMP_FLOOR but never ABOVE the rolled count — damping must only
			# ever shrink a wave (a count-1 roll stays 1, it doesn't get "floored" up to 2).
			count = clampi(int(round(float(count) * damp)), mini(count, ARMED_DAMP_FLOOR), count)
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
	# Shared roster-behavior stamp (shoot/components/fire/stats/locomotion/mounts) — one impl in
	# formation_shapes, also used by authored_patterns._spec_for_placement (dedup, review §3).
	# Mounts moved INTO the shared stamp 2026-07-07 so authored placements arm their enemies too
	# (roster mounts are the only weapon source post-consolidation); the stamp respects an explicit
	# pre-set mounts_override, so a wave-level weapon override still wins.
	FormationShapesC.stamp_roster_behavior(w, entry)
	# DIVERGENT extras (not in the shared block, this path only):
	# Chaff roll-back: combat chaff RECYCLE a couple of times (fly back + re-enter) so missed enemies
	# feed the next sub-wave and ~300 enemies fill ~3 min, rather than leaking off the bottom in ~60s.
	# Overrides the roster's recycle:0 for high-count chaff (see CHAFF_RECYCLE_PASSES). Boss lead-ins
	# keep their own tuning.
	if not is_boss_leadin and bool(entry.get("chaff", false)) and CHAFF_RECYCLE_PASSES > 0:
		w.recycle_passes = CHAFF_RECYCLE_PASSES
	# Depth: a random wave has no formation depth override, so the enemy's roster-default depth
	# (compose_stats depth_bp) rides depth_override.
	w.depth_override = float(Roster.compose_stats(entry).get("depth_bp", -1.0))
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
