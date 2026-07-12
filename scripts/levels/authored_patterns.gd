extends Object

# Authored wave-pattern library + builder (wave pattern editor, 2026-06-16).
#
# A "pattern" is a single FORMATION burst: enemies placed on explicit lanes with optional
# per-enemy entry stagger. Each slot's ENEMY and MOVEMENT are each either SPECIFIC or a
# WILDCARD ("" = conductor-assigned), which yields three authoring modes from one mechanism:
#   - enemies fixed / movement wildcard  -> you pick who+where, conductor sets movements
#   - enemies wildcard / movement fixed  -> you pick the shape, conductor fills faction enemies
#   - both fixed                         -> premade, performed as-is
#
# build_phrase() compiles a pattern dict -> a FORMATION Phrase (shape &"authored") that the
# conductor performs via director._dispatch_authored. Wildcards resolve HERE, seeded by an
# RNG drawn from the content stream, so a same-seed run reproduces the realization.
#
# DATA is the committed library; the wave pattern editor (scripts/dev/wave_pattern_editor.gd)
# exports a paste-ready `const DATA` here, mirroring pattern_eligibility.gd. Preload-referenced,
# NOT a class_name (headless-safe, matching factions.gd / lane_traffic).

const WaveSpecScript = preload("res://scripts/levels/wave_def.gd")
const Roster = preload("res://scripts/levels/enemy_roster.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const Lanes = preload("res://scripts/systems/lanes.gd")
const FormationShapesC = preload("res://scripts/levels/formation_shapes.gd")

# Per-wave probability the auto-mix splices an authored pattern into a generated wave.
const DEFAULT_CHANCE := 0.22

# Fairness clamp (conductor review §2.1, 2026-07-02): an injected formation is INVISIBLE to the
# stretch slot-budget, so a 21-33-member wall used to burst on top of a capstone at the 36-slot
# climax (or worse under the 16-slot opener). At injection time we skip patterns whose member count
# exceeds this SHARE of the wave's slot_cap — the injection should be an accent on the wave, never a
# second wave's worth of enemies. Skipping (not trimming) preserves each authored shape's designed
# whole (navigability guarantees). Dev-forced patterns bypass this (explicit intent).
const INJECT_CAP_SHARE := 0.6
# Fallback cap when a ScoreWave carries no slot_cap (-1 = hazards / non-stretch content). Matches the
# director's export default so the share math stays sane off the 3-stretch path.
const INJECT_FALLBACK_CAP := 14

# Faction NAME -> Factions.Id. "any"/"" -> -1 (no fill faction / matches any level).
const FACTION_IDS := {
	"supremacy": Factions.Id.SUPREMACY,
	"privateer": Factions.Id.PRIVATEER,
	"corporate": Factions.Id.CORPORATE,
	"zealot": Factions.Id.ZEALOT,
}

# The committed pattern library — authored in the wave pattern editor, named + baked here (Roman
# 2026-06-17). 23 conductor-filled formations (incl. weave/cut/collapsing/escort variants) spanning the movement families: charge_* (fast straight
# spearhead / wall / echelon), loiter_* (held tiers / phalanx), drift/shift/hook lattices, crawl_*
# (slow phalanx / hourglass / weave), and advance_* (medium straight pairs / chevron / columns).
# All faction "any", min_sector 0 — auto-mixed into generated waves by maybe_inject().
const DATA: Array = [
	{
		"name": "v_pincer_delayed",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 5, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 5, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 1, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
		],
	},
	{
		"name": "charge_spearhead",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
		],
	},
	{
		"name": "charge_wall",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 6, "row": 5, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 0, "row": 5, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 2, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 2, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
		],
	},
	{
		"name": "charge_echelon",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 2, "row": 2, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 5, "row": 5, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "straight_charge", "size": "small"},
			{"lane": 0, "row": 0, "enemy": "", "movement": "straight_charge", "size": "small"},
		],
	},
	{
		"name": "loiter_tiers",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "loiter_low", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "loiter_low", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "loiter_low", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "loiter_low", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "loiter_mid", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "loiter_mid", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "loiter_mid", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "loiter_high", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "loiter_high", "size": "small"},
		],
	},
	{
		"name": "loiter_phalanx",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 0, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 6, "row": 2, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 6, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
			{"lane": 0, "row": 4, "enemy": "", "movement": "loiter", "size": "small"},
		],
	},
	{
		"name": "drift_lattice",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 6, "row": 5, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 0, "row": 5, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "lane_drift", "size": "small"},
		],
	},
	{
		"name": "shift_columns",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 5, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
		],
	},
	{
		"name": "hook_trident",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 3, "row": 5, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "lane_hook", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_hook", "size": "small"},
		],
	},
	{
		"name": "crawl_phalanx",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 6, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
		],
	},
	{
		"name": "crawl_hourglass",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
		],
	},
	{
		"name": "crawl_weave",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 2, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 4, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "straight_crawl", "size": "small"},
		],
	},
	{
		"name": "shift_cross_pair",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"placements": [
			{"lane": 1, "row": 5, "enemy": "", "movement": "lane_shift", "size": "medium"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_shift", "size": "medium"},
		],
	},
	{
		"name": "advance_cross_pair",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 1, "row": 5, "enemy": "", "movement": "straight_slow", "size": "medium"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "straight_slow", "size": "medium"},
		],
	},
	{
		"name": "advance_chevron",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 3, "row": 5, "enemy": "", "movement": "straight_medium", "size": "medium"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 2, "row": 3, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 4, "row": 3, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "straight_medium", "size": "small"},
		],
	},
	{
		"name": "advance_columns",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 5, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "straight_medium", "size": "small"},
			{"lane": 3, "row": 5, "enemy": "", "movement": "straight_slow", "size": "medium"},
		],
	},
	{
		"name": "weave_middle",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 3, "row": 0, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
		],
	},
	{
		"name": "weave_wave",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 6, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 0, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 6, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 4, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 2, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 4, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 2, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_weave", "size": "small"},
		],
	},
	{
		"name": "collapsing_line",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 1, "row": 0, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 1, "row": 5, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 1, "row": 3, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 3, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 5, "row": 5, "enemy": "", "movement": "lane_drift", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 3, "row": 5, "enemy": "", "movement": "lane_weave", "size": "small"},
			{"lane": 0, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 0, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "lane_shift", "size": "small"},
			{"lane": 6, "row": 2, "enemy": "", "movement": "lane_shift", "size": "small"},
		],
	},
	{
		"name": "cut_right_high",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
			{"lane": 5, "row": 5, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "right", "depth": "high"},
		],
	},
	{
		"name": "cut_left_high",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 6, "row": 0, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
			{"lane": 1, "row": 5, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "left", "depth": "high"},
		],
	},
	{
		"name": "loiter_tiered",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 5, "enemy": "", "movement": "loiter_sweep", "size": "medium", "dir": "random", "depth": "low"},
			{"lane": 0, "row": 3, "enemy": "", "movement": "loiter_sweep", "size": "medium", "dir": "random", "depth": "mid"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "loiter_sweep", "size": "medium", "dir": "random", "depth": "high"},
		],
	},
	{
		"name": "straight_escort_wall",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": true,
		"placements": [
			{"lane": 0, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 1, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 2, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 3, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 4, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 5, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 6, "row": 5, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 0, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 2, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 4, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 6, "row": 4, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 1, "row": 3, "enemy": "", "movement": "straight", "size": "medium"},
			{"lane": 3, "row": 3, "enemy": "", "movement": "straight", "size": "medium"},
			{"lane": 5, "row": 3, "enemy": "", "movement": "straight", "size": "medium"},
			{"lane": 2, "row": 2, "enemy": "", "movement": "straight", "size": "medium"},
			{"lane": 4, "row": 2, "enemy": "", "movement": "straight", "size": "medium"},
			{"lane": 0, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 1, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 2, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 3, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 4, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 5, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 6, "row": 1, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 6, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 4, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 2, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 1, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
			{"lane": 0, "row": 0, "enemy": "", "movement": "straight", "size": "small"},
		],
	},
	{
		# Depth-banding exemplar (baked from user://tuners/wave_patterns.json, 2026-07-02): 9 lane-cutters
		# on the parity lanes 1/3/5 × rows 0/2/4, each row's depth band monotonic high→mid→low. Free (not
		# lockstep) so each cutter runs at its own chassis speed. Leaves lanes 0/2/4/6 clear = navigable.
		"name": "lane_cut_wave",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 1, "row": 0, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "high"},
			{"lane": 3, "row": 0, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "high"},
			{"lane": 5, "row": 0, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "high"},
			{"lane": 1, "row": 2, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "mid"},
			{"lane": 3, "row": 2, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "mid"},
			{"lane": 5, "row": 2, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "mid"},
			{"lane": 1, "row": 4, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "low"},
			{"lane": 3, "row": 4, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "low"},
			{"lane": 5, "row": 4, "enemy": "", "movement": "lane_cut", "size": "small", "dir": "", "depth": "low"},
		],
	},
	{
		"name": "asteroid_1",
		"faction": "hazard",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_left",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_right",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_sides",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 5, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_center",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_arrow",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_line_1",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_channel_2",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_channel",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "asteroid_channel_3",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 1, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 5, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 0, "enemy": "res://scenes/enemies/enemy_asteroid.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "mine_narrow_lane",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "mine_lane_wide",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "mine_X",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 6, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "mine_heart",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 1, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 6, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 0, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
		],
	},
	{
		"name": "mine_diamond",
		"faction": "any",
		"min_sector": 0,
		"stagger": 0.18,
		"lockstep": false,
		"placements": [
			{"lane": 3, "row": 5, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 0, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 3, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 1, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 2, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 4, "row": 4, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 3, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 1, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
			{"lane": 5, "row": 2, "enemy": "res://scenes/enemies/enemy_mine.tscn", "movement": "straight", "size": ""},
		],
	},
]


# Map a faction NAME to a Factions.Id, or -1 for "any"/unknown.
static func faction_id(fname: String) -> int:
	return int(FACTION_IDS.get(fname, -1))


# Patterns eligible to auto-mix into a level: min_sector reached AND faction matches. A
# pattern with faction "any" fits any level; otherwise its faction must equal the level's.
# `level_faction` is the Factions.Id of the level (-1 = none / headless).
static func eligible(level_faction: int, sector: int) -> Array:
	var out: Array = []
	for p in DATA:
		if int(p.get("min_sector", 0)) > sector:
			continue
		var pf: String = String(p.get("faction", "any"))
		# Hazard layouts go to hazard FIELDS only — never the combat auto-mix (they'd spawn rogue
		# asteroids/mines mid-wave). Classify by CONTENT, not the faction tag: the wave editor defaults
		# new patterns to "any", so asteroid/mine layouts are routinely mis-tagged (only the pinned
		# scene is trustworthy — verified 2026-06-23, 14 of 15 hazard patterns were tagged "any").
		if pf == "hazard" or _is_hazard_pinned(p):
			continue
		if pf == "any" or pf == "" or faction_id(pf) == level_faction:
			out.append(p)
	return out


# Authored HAZARD patterns: asteroid/mine layouts Roman hand-places in the wave editor, spliced into
# hazard FIELDS by levels_v2 (the conductor's authored dispatch places them at exact lanes, navigable
# by construction). Detected by CONTENT — any placement that pins an asteroid/mine/bomblet scene —
# NOT the faction tag (see _is_hazard_pinned). `kind` filters by the pinned scene substring
# ("asteroid" / "mine"); "" returns all. Excluded from eligible() so they never auto-mix into combat.
static func hazard_patterns(kind: String = "", sector: int = 9999) -> Array:
	var out: Array = []
	for p in DATA:
		if not _is_hazard_pinned(p):
			continue
		if int(p.get("min_sector", 0)) > sector:
			continue
		if kind != "" and not _first_scene(p).to_lower().contains(kind):
			continue
		out.append(p)
	return out


# True if any placement pins an asteroid/mine/bomblet scene — the CONTENT signal that a pattern is a
# hazard FIELD layout rather than a general combat formation. Authoritative over the faction tag.
static func _is_hazard_pinned(p: Dictionary) -> bool:
	for pl in p.get("placements", []):
		var e: String = String(pl.get("enemy", "")).to_lower()
		if e.contains("asteroid") or e.contains("mine") or e.contains("bomblet"):
			return true
	return false


static func _first_scene(p: Dictionary) -> String:
	var pls: Array = p.get("placements", [])
	return String(pls[0].get("enemy", "")) if not pls.is_empty() else ""


# Compile a pattern dict into a FORMATION Phrase (shape &"authored"). Wildcards resolve here,
# seeded by `rng`: a "" enemy picks a fill_faction/sector/size-appropriate roster entry; a ""
# movement uses the entry's roster default; specified values are honoured. `fill_faction` is the
# level's Factions.Id (-1 = no faction filter). Returns null if nothing resolves.
static func build_phrase(pattern: Dictionary, fill_faction: int, sector: int, rng: RandomNumberGenerator) -> Phrase:
	var lockstep: bool = bool(pattern.get("lockstep", false))
	var placements: Array = pattern.get("placements", [])
	# Entry order reads bottom-up (Roman 2026-06-23): the BOTTOM-most painted row leads on screen
	# (enters first), the TOP row trails — so the burst appears as drawn, "sheet music" style.
	var max_row: int = 0
	for pl in placements:
		max_row = maxi(max_row, int(pl.get("row", 0)))
	var specs: Array = []
	for pl in placements:
		var ws = _spec_for_placement(pl, fill_faction, sector, max_row, rng)
		if ws != null:
			specs.append(ws)
	if specs.is_empty():
		return null
	# Formation speed mode (Formation Builder, 2026-06-22): "formation"/lockstep makes the whole
	# burst advance at the SLOWEST member's speed so it holds its shape; "free" (the default, and
	# every legacy pattern w/o the key) leaves each unit at its own chassis speed.
	if lockstep:
		FormationShapesC.lock_to_slowest(specs)
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.shape = &"authored"
	ph.specs = specs
	return ph


# Build one count-1 WaveSpec for a single placement, resolving enemy + movement. Returns null
# when the slot can't be filled (no eligible enemy / unloadable scene).
static func _spec_for_placement(pl: Dictionary, fill_faction: int, sector: int, max_row: int, rng: RandomNumberGenerator):
	var enemy_path: String = String(pl.get("enemy", ""))
	var move_key: String = String(pl.get("movement", ""))
	# Collapse legacy speed/depth-variant keys to their SHAPE the same way make_movement does, so
	# eligibility (which is keyed on shapes) can judge the placement's movement. Raw move_key is kept
	# for the banded-depth suffix + hazard drift_mode logic below.
	var collapsed_key: String = String(Roster.MOVEMENT_ALIASES.get(move_key, move_key))
	var size_hint: String = String(pl.get("size", ""))
	var entry: Dictionary = {}
	if enemy_path != "":
		entry = Roster.entry_for_scene(enemy_path)
	else:
		# Primary guard (shape-preserving): a fixed-movement wildcard only fills with enemies whose
		# eligibility actually permits that movement — a crossing shape (lane_cut/side_traverse) can't
		# land on a hold-class unit whose matrix forbids it (the bug this fixes).
		entry = _pick_wildcard_entry(fill_faction, sector, size_hint, collapsed_key, rng)
		if not entry.is_empty():
			enemy_path = String(entry.get("scene", ""))
	if enemy_path == "":
		return null
	var scene := load(enemy_path) as PackedScene
	if scene == null:
		return null

	var ws := WaveSpecScript.new()
	ws.enemy_scene = scene
	ws.count = 1
	ws.lane = int(pl.get("lane", -1))
	ws.spawn_delay = 0.0   # whole formation spawns together; row spacing is SPATIAL (spawn_y below)
	# Sub-grid within the lane square (Formation Builder): sub_x spreads horizontally within the
	# lane, sub_y nudges the spawn height so a cell enters as a cluster. Centre (1,1) = legacy.
	var sub_x: int = int(pl.get("sub_x", 1))
	var sub_y: int = int(pl.get("sub_y", 1))
	ws.spawn_x_offset = (float(sub_x) - 1.0) * (Lanes.WIDTH / 3.0)
	# Pre-stack rows ABOVE the top edge so the painted formation descends in intact: the bottom-most
	# painted row (row == max_row) enters at the edge; each row up adds one shared ROW_GAP
	# (formation_shapes.prestack_y — dedup, review §3). sub_y nudges within the row. enemy_base
	# suppresses the FREE_ANY_EDGE top cull until first entry so these aren't freed pre-descent.
	var row: int = int(pl.get("row", 0))
	ws.spawn_y = FormationShapesC.prestack_y(row, max_row) + (float(sub_y) - 1.0) * 11.0
	# Lateral-direction override (Formation Builder): "left"/"right"/"random" force which way a
	# side-aware movement runs; "" / "any" leaves it as authored. director._apply_direction consumes it.
	match String(pl.get("dir", "")):
		"right": ws.direction_override = 1
		"left": ws.direction_override = -1
		"random": ws.direction_override = 2
		_: ws.direction_override = 0

	# Movement: an explicit key overrides (resolved scene-less so the matrix identity can't
	# stomp it — same trick the eligibility editor's preview uses); else the entry's roster
	# default. Leave the scene's authored movement when neither applies (non-roster enemy).
	if move_key != "":
		# Secondary guard (coercion net): route the collapsed key through eligibility before building
		# the override. Catches wildcard fills whose primary filter had to fall back to the unfiltered
		# pool AND authored fixed-enemy + fixed-movement mismatches. Fail-open scenes/keys pass through.
		var guarded_key: String = PatternEligibility.guard_key(enemy_path, collapsed_key)
		ws.movement_override = Roster.make_movement({"movement": guarded_key})
		# Also carry the key as a hazard drift mode: for a self-drifting hazard (asteroid/mine/firecore)
		# the movement_override Resource is inert (no movement slot), and director._spawn_enemy instead
		# reads drift_mode to pick the LateralDrift envelope. Harmless for non-hazards (no drift_mode
		# property). So an authored asteroid channel with movement "straight" actually holds its lane.
		ws.drift_mode = move_key
	elif not entry.is_empty():
		ws.movement_override = Roster.make_movement(entry)

	# Shoot / components / stats from the roster entry so a filled enemy behaves like a normal spawn.
	# The shared block (shoot/components/fire/stats/locomotion) is stamped by formation_shapes; the
	# per-placement DEPTH override below is authored-only. Skipped for non-roster scenes.
	if not entry.is_empty():
		FormationShapesC.stamp_roster_behavior(ws, entry)
		var stats: Dictionary = Roster.compose_stats(entry)
		# Depth: an explicit placement "depth" wins; else a legacy banded movement key
		# (loiter_low → "low") carries the band; else the enemy's roster-default depth.
		var pl_depth: Variant = pl.get("depth", null)
		if (pl_depth == null or String(pl_depth) == "") and move_key != "":
			if move_key.ends_with("_high"):
				pl_depth = "high"
			elif move_key.ends_with("_mid"):
				pl_depth = "mid"
			elif move_key.ends_with("_low"):
				pl_depth = "low"
		if pl_depth != null and String(pl_depth) != "":
			ws.depth_override = Zones.depth_to_bp(pl_depth, float(stats.get("depth_bp", -1.0)))
		else:
			ws.depth_override = float(stats.get("depth_bp", -1.0))
	return ws


# Pick a roster entry to fill a wildcard slot: eligible in `fill_faction` at `sector`, matching
# `size_hint` when given (falls back to any size if none match), and — when `move_key` is set —
# restricted to enemies whose PatternEligibility permits that (alias-collapsed) movement. Seeded by
# `rng`. {} if empty.
static func _pick_wildcard_entry(fill_faction: int, sector: int, size_hint: String, move_key: String, rng: RandomNumberGenerator) -> Dictionary:
	var prev: int = Roster.get_faction_filter()
	Roster.set_faction_filter(fill_faction)
	var pool: Array = []
	for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON, Roster.Tier.RARE]:
		pool += Roster.entries_eligible(tier, sector, 99)
	Roster.set_faction_filter(prev)
	if pool.is_empty():
		return {}
	# Movement-eligibility filter (primary guard). allows() fails open for unmapped scenes + path_*
	# keys, so this only prunes when the matrix actively forbids the movement for a scene. If the
	# filter empties the pool, log and fall back to the unfiltered pool — the guard_key coercion net
	# at the stamp site then repairs whatever gets picked.
	if move_key != "":
		var moved: Array = pool.filter(func(e): return PatternEligibility.allows(String(e.get("scene", "")), move_key))
		if not moved.is_empty():
			pool = moved
		else:
			push_error("AuthoredPatterns._pick_wildcard_entry: no faction=%d enemy eligible for movement '%s' — falling back to unfiltered pool." % [fill_faction, move_key])
	if size_hint != "":
		var sized: Array = pool.filter(func(e): return String(e.get("size", "")) == size_hint)
		if not sized.is_empty():
			pool = sized
	return pool[rng.randi() % pool.size()]


# Auto-mix: roll a seeded chance PER WAVE to splice an eligible authored pattern's phrase into the
# generated score, so authored patterns appear in normal play alongside the random ones. Mutates
# `score` in place. `fill_faction` = the level's Factions.Id (-1 = none); `sector` = sector depth;
# `rng` MUST be drawn from the content-seed stream so a node-retry reproduces the injection.
#   Dev one-shot: Run meta "forced_pattern" (a pattern name, set by the editor's "send to
#   conductor") forces THAT pattern into wave 0 and skips the roll (consumed once).
static func maybe_inject(score, fill_faction: int, sector: int, rng: RandomNumberGenerator, chance: float = DEFAULT_CHANCE, motif: Dictionary = {}) -> void:
	if score == null or score.waves.is_empty():
		return
	var fp: Dictionary = _forced()
	if not fp.is_empty():
		var ph0 := build_phrase(fp, fill_faction, sector, rng)
		if ph0 != null:
			score.waves[0].phrases.append(ph0)
		return
	var pool: Array = eligible(fill_faction, sector)
	if pool.is_empty():
		return
	# MOTIF FILTER (review §5, roadmap P2.7): when a LevelMotif is supplied, PREFER injected patterns
	# that share the motif's signature movement key (so injections reinforce the level's recurring
	# behavior instead of randomizing it). This is a PREFERENCE, not a hard requirement — if no eligible
	# pattern matches the motif key, fall back to the full pool. Determinism: the pool we draw from is a
	# pure function of (fill_faction, sector, motif), so a node retry reproduces the picks. The size
	# filter + unconditional-draw convention below are unchanged.
	var motif_pool: Array = _motif_filtered(pool, motif)
	if not motif_pool.is_empty():
		pool = motif_pool
	for w in score.waves:
		if rng.randf() < chance:
			# Down-select to patterns that FIT this wave's cap headroom (fairness §2.1): an injection is
			# an accent, not a second wave. Draw the RNG unconditionally (fit or not) so the injection
			# stream stays deterministic across the size filter — a node retry reproduces the same picks.
			var pat: Dictionary = pool[rng.randi() % pool.size()]
			# FIX 1 (2026-07-06): SKIP a wave that already got a motif capstone (tagged by
			# inject_motif_capstones). Two guaranteed-plus-accent pre-stacked bursts on one stretch
			# boundary was the worst-case bunching (~45 members vs a 44 ceiling). Draw the RNG FIRST
			# (above) so the skip is draw-then-discard — the seeded stream stays deterministic across
			# the prune (a node retry reproduces every subsequent pick).
			if w.has_meta("motif_capstoned"):
				continue
			var cap: int = int(w.slot_cap) if ("slot_cap" in w and int(w.slot_cap) >= 0) else INJECT_FALLBACK_CAP
			var max_members: int = maxi(1, int(float(cap) * INJECT_CAP_SHARE))
			if _member_count(pat) > max_members:
				continue   # oversized for this wave — skip rather than mutilate the authored shape
			var ph := build_phrase(pat, fill_faction, sector, rng)
			if ph != null:
				w.phrases.append(ph)


# Placement count of a pattern dict (its member count once built). Used to gate injection against
# the wave's cap headroom — see INJECT_CAP_SHARE.
static func _member_count(pattern: Dictionary) -> int:
	return (pattern.get("placements", []) as Array).size()


# Down-select `pool` to library patterns whose DOMINANT movement key matches the motif's signature
# key (review §5 motif reinforcement). Returns [] when no motif key is given or nothing matches — the
# caller then keeps the full pool (preference, not requirement). A pattern's dominant key = the most
# common `movement` across its placements.
static func _motif_filtered(pool: Array, motif: Dictionary) -> Array:
	var key: String = String(motif.get("movement", ""))
	if key == "":
		return []
	var out: Array = []
	for p in pool:
		if _dominant_movement(p) == key:
			out.append(p)
	return out


static func _dominant_movement(pattern: Dictionary) -> String:
	var counts: Dictionary = {}
	var best: String = ""
	var best_n: int = 0
	for pl in pattern.get("placements", []):
		var mv: String = String(pl.get("movement", ""))
		if mv == "":
			continue
		counts[mv] = int(counts.get(mv, 0)) + 1
		if int(counts[mv]) > best_n:
			best_n = int(counts[mv]); best = mv
	return best


# Splice the LevelMotif's pre-composed escalation capstones (roadmap P2.7) onto the score as native
# authored phrases. Each `variants[stretch]` is an AuthoredPatterns-schema pattern dict from
# FormationComposer; it compiles here via build_phrase() (the same path authored patterns take) and is
# appended as the FINAL phrase of that stretch's ScoreWave. ScoreWaves map 1:1 to stretches (each
# stretch opens exactly one ScoreWave, review §5 / level_structure_redesign), so score.waves[stretch]
# is the capstone target. Empty variants (composition failed) are skipped — the in-line random
# shape_override capstone already stands as the fallback for that stretch. `rng` MUST be the content
# stream (same convention as maybe_inject) so a node retry reproduces the realized capstone.
static func inject_motif_capstones(score, variants: Array, fill_faction: int, sector: int, rng: RandomNumberGenerator) -> void:
	if score == null or score.waves.is_empty():
		return
	for stretch in variants.size():
		if stretch >= score.waves.size():
			break
		var v: Dictionary = variants[stretch]
		if v.is_empty() or (v.get("placements", []) as Array).is_empty():
			continue
		var ph := build_phrase(v, fill_faction, sector, rng)
		if ph != null:
			score.waves[stretch].phrases.append(ph)
			# FIX 1 (2026-07-06): mark this ScoreWave so maybe_inject SKIPS it — a wave that already
			# got a guaranteed motif capstone must not ALSO receive a 22% maybe_inject accent, or the
			# two pre-stacked bursts stack against one cap at the same stretch boundary (bunching).
			score.waves[stretch].set_meta("motif_capstoned", true)


# Read + clear the dev "send to conductor" one-shot. The editor can push EITHER a live pattern
# dict (Run.forced_pattern_dict, no export needed) OR a committed name (Run.forced_pattern).
static func _forced() -> Dictionary:
	var run := _run_node()
	if run == null:
		return {}
	if run.has_meta("forced_pattern_dict"):
		var d = run.get_meta("forced_pattern_dict", {})
		run.remove_meta("forced_pattern_dict")
		if d is Dictionary and not (d as Dictionary).is_empty():
			return d
	if run.has_meta("forced_pattern"):
		var nm: String = String(run.get_meta("forced_pattern", ""))
		run.remove_meta("forced_pattern")
		return _by_name(nm)
	return {}


static func _run_node() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var root := (ml as SceneTree).root
	return root.get_node_or_null("Run") if root != null else null


static func _by_name(nm: String) -> Dictionary:
	for p in DATA:
		if String(p.get("name", "")) == nm:
			return p
	return {}
