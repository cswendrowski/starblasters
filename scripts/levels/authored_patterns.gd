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
const Factions = preload("res://scripts/levels/factions.gd")
const Lanes = preload("res://scripts/systems/lanes.gd")

# Per-wave probability the auto-mix splices an authored pattern into a generated wave.
const DEFAULT_CHANCE := 0.22

# Vertical gap (px) between formation rows: rows are pre-stacked this far apart ABOVE the screen so
# the painted formation descends in holding its shape (~ the editor grid's row height; tunable).
const ROW_GAP_PX := 40.0

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
		if pf == "any" or pf == "" or faction_id(pf) == level_faction:
			out.append(p)
	return out


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
		_lock_to_slowest(specs)
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.shape = &"authored"
	ph.specs = specs
	return ph


# Lockstep speed: clamp every speed-bearing spec to the SLOWEST member's move_speed so an authored
# formation advances in unison instead of spreading out as fast units outrun slow ones. Specs with
# no resolved speed (move_speed <= 0 — e.g. non-roster scenes that keep their scene-baked motion)
# are left untouched, and don't drag the minimum to zero.
static func _lock_to_slowest(specs: Array) -> void:
	var slowest: float = INF
	for ws in specs:
		if ws.move_speed > 0.0:
			slowest = minf(slowest, ws.move_speed)
	if slowest == INF:
		return   # nothing had a resolved speed
	for ws in specs:
		if ws.move_speed > 0.0:
			ws.move_speed = slowest


# Build one count-1 WaveSpec for a single placement, resolving enemy + movement. Returns null
# when the slot can't be filled (no eligible enemy / unloadable scene).
static func _spec_for_placement(pl: Dictionary, fill_faction: int, sector: int, max_row: int, rng: RandomNumberGenerator):
	var enemy_path: String = String(pl.get("enemy", ""))
	var move_key: String = String(pl.get("movement", ""))
	var size_hint: String = String(pl.get("size", ""))
	var entry: Dictionary = {}
	if enemy_path != "":
		entry = Roster.entry_for_scene(enemy_path)
	else:
		entry = _pick_wildcard_entry(fill_faction, sector, size_hint, rng)
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
	# painted row (row == max_row) enters at the edge; each row up adds ROW_GAP_PX. enemy_base
	# suppresses the FREE_ANY_EDGE top cull until first entry so these aren't freed pre-descent.
	var row: int = int(pl.get("row", 0))
	ws.spawn_y = -12.0 - float(max_row - row) * ROW_GAP_PX + (float(sub_y) - 1.0) * 11.0
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
		ws.movement_override = Roster.make_movement({"movement": move_key})
	elif not entry.is_empty():
		ws.movement_override = Roster.make_movement(entry)

	# Shoot / components / stats from the roster entry so a filled enemy behaves like a normal
	# spawn (mirrors wave_generator._make_wave_spec). Skipped for non-roster scenes.
	if not entry.is_empty():
		var sp = Roster.make_shoot(entry)
		if sp != null:
			ws.shoot_pattern_override = sp
		ws.components_override = Roster.make_components(entry) + Roster.make_emitters(entry)
		if entry.has("fire_min"):
			ws.fire_interval_min = float(entry["fire_min"])
		if entry.has("fire_max"):
			ws.fire_interval_max = float(entry["fire_max"])
		var stats: Dictionary = Roster.compose_stats(entry)
		ws.max_health = int(stats["max_health"])
		ws.bounty_value = int(stats["bounty_value"])
		if int(stats["shield_charges"]) > 0:
			ws.shield_charges = int(stats["shield_charges"])
		if int(stats["recycle_passes"]) >= -1:
			ws.recycle_passes = int(stats["recycle_passes"])
		# Locomotion (chassis stats). A placement "depth" override wins over the enemy's
		# roster-default depth; otherwise the roster default (compose_stats depth_bp) rides through.
		ws.move_speed = float(stats.get("move_speed", 0.0))
		ws.weight = float(stats.get("weight", 0.0))
		ws.turn_rate = float(stats.get("turn_rate", 0.0))
		ws.accel = float(stats.get("accel", 0.0))
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
# `size_hint` when given (falls back to any size if none match). Seeded by `rng`. {} if empty.
static func _pick_wildcard_entry(fill_faction: int, sector: int, size_hint: String, rng: RandomNumberGenerator) -> Dictionary:
	var prev: int = Roster.get_faction_filter()
	Roster.set_faction_filter(fill_faction)
	var pool: Array = []
	for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON, Roster.Tier.RARE]:
		pool += Roster.entries_eligible(tier, sector, 99)
	Roster.set_faction_filter(prev)
	if pool.is_empty():
		return {}
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
static func maybe_inject(score, fill_faction: int, sector: int, rng: RandomNumberGenerator, chance: float = DEFAULT_CHANCE) -> void:
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
	for w in score.waves:
		if rng.randf() < chance:
			var pat: Dictionary = pool[rng.randi() % pool.size()]
			var ph := build_phrase(pat, fill_faction, sector, rng)
			if ph != null:
				w.phrases.append(ph)


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
