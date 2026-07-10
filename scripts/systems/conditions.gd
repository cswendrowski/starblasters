class_name Conditions
extends RefCounted

# Sector Conditions — the reusable vocabulary + aggregation core.
#
# A Condition is a deal the player opts into: it carries a signed Threat value
# and a DECLARATIVE `mods` payload. Gameplay effect sites (director, player,
# outpost — built as separate work packages) read the aggregate of the active
# Conditions ONLY through the generic aggregators below (scalar / sum / flag /
# union) — never via per-id match statements. This file is the single source
# of truth for the Condition vocabulary going forward (supersedes the legacy
# strings.gd MODIFIER_LABELS, which is left untouched behind the kill-switch).
#
# Design: docs/sector_conditions_redesign_2026-07-06.md. All helpers are static
# (mirror scripts/systems/clarity.gd) — call as `Conditions.scalar(...)`.
#
# `mods` value conventions (each aggregated by a matching helper):
#   * multiplicative keys → aggregate by PRODUCT   (scalar), e.g. "player.damage_taken_mult": 2.0
#   * additive keys       → aggregate by SUM        (sum),    e.g. "enemy.rung_delta": 1
#   * flag keys           → aggregate by ANY-TRUE   (flag),   e.g. "player.glass_hull": true
#   * list keys           → aggregate by UNION      (union),  e.g. "pool.block_slots": ["CANNON"]

# --- Reward-model knobs (first-pass; tuner-bound — see design §5) ---
# reward coupling cut 2026-07-09 (Roman) — difficulty is self-motivated; the
# award_bounty/award_combat_materials choke points + these dials stay in place if
# it ever returns. Both K set to 0.0 → bounty_mult/materials_mult are identity
# (1.0) at any net Threat, so no payout scaling is applied anywhere.
const K_BOUNTY := 0.0     # tuner-bound (coupling cut — 0.08 to re-enable)
const K_MATERIALS := 0.0  # tuner-bound (coupling cut — 0.06 to re-enable)

# Valid `bucket` values — validate() rejects anything outside this set.
const BUCKETS := [
	"enemy_bane", "fragility_bane", "loadout_bane",
	"player_boon", "economy_pair", "grant",
]

# Valid `category` values — the front-end groups the picker into these three columns
# (enemy behaviour / player loadout+survivability / economy). validate() rejects anything
# outside this set. NOTE: category is orthogonal to `bucket` and to threat sign — e.g.
# Slow Enemies is a player_boon but an "enemy" category (it changes enemy behaviour).
const CATEGORIES := ["enemy", "player", "economy"]

# id → entry. Entry shape:
#   { "label": String, "blurb": String, "threat": int (signed),
#     "group": String (mutex group; "" = none), "bucket": String,
#     "category": String ("enemy"|"player"|"economy"), "mods": Dictionary }
# Labels/blurbs are the player-facing vocabulary SSOT (names verbatim from the
# design doc). Economy-pair numbers + grant amounts are first-pass, tuner-bound.
const CATALOG := {
	# ── 4a. Enemy banes ──────────────────────────────────────────────────────
	"armored": {
		"label": "Armored", "threat": 2, "group": "enemy_toughness", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Elite enemies shrug off a slice of incoming damage.",
		"mods": {"enemy.dr_floor": 0.10},
	},
	"armored_heavies": {
		"label": "Armored Heavies", "threat": 2, "group": "enemy_toughness", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Non-chaff enemies have 50% more hull.",
		"mods": {"enemy.heavy_hp_mult": 1.5},
	},
	"shielded": {
		"label": "Shielded", "threat": 2, "group": "", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Elite enemies carry an extra shield charge.",
		"mods": {"enemy.shield_bonus": 1},
	},
	"trigger_happy": {
		"label": "Trigger-Happy", "threat": 2, "group": "", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Enemies fire faster (−15% between shots).",
		"mods": {"enemy.fire_interval_mult": 0.85},
	},
	"fast_enemies": {
		"label": "Fast Enemies", "threat": 2, "group": "enemy_speed", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Enemy ships move one speed rung faster.",
		"mods": {"enemy.rung_delta": 1},
	},
	"fast_bullets": {
		"label": "Fast Bullets", "threat": 2, "group": "bullet_speed", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Enemy fire travels one speed rung faster.",
		"mods": {"bullet.rung_delta": 1},
	},
	"heavy_escort": {
		"label": "Heavy Escort", "threat": 2, "group": "", "bucket": "enemy_bane", "category": "enemy",
		"blurb": "Supremacy patrols field rare cruisers far more often.",
		"mods": {"cruiser.encounter_mult": 2.75},  # tuner-bound
	},

	# ── 4b. Player-fragility banes ───────────────────────────────────────────
	"glass_patrol": {
		"label": "Glass Patrol", "threat": 5, "group": "", "bucket": "fragility_bane", "category": "player",
		"blurb": "Any hull damage is instant death. Hull modules are pulled from the pool.",
		"mods": {"player.glass_hull": true, "pool.block_hull_modules": true},
	},
	"heavy_ordnance": {
		"label": "Heavy Ordnance", "threat": 4, "group": "", "bucket": "fragility_bane", "category": "player",
		"blurb": "All damage you take counts double.",
		"mods": {"player.damage_taken_mult": 2.0},
	},
	"weak_shields": {
		"label": "Weak Shields", "threat": 3, "group": "shield_strength", "bucket": "fragility_bane", "category": "player",
		"blurb": "Your shield starts with half its charges.",
		"mods": {"player.shield_charges_mult": 0.5},
	},
	"weak_weapons": {
		"label": "Weak Weapons", "threat": 3, "group": "weapon_damage", "bucket": "fragility_bane", "category": "player",
		"blurb": "Your weapon damage is halved.",
		"mods": {"player.weapon_damage_mult": 0.5},
	},

	# ── 4c. Loadout-restriction banes (independent slots — may stack) ─────────
	"no_primaries": {
		"label": "No Primaries", "threat": 2, "group": "", "bucket": "loadout_bane", "category": "player",
		"blurb": "No primary cannons roll or drop. Keep your blaster.",
		"mods": {"pool.block_slots": ["CANNON"]},
	},
	"no_secondaries": {
		"label": "No Secondaries", "threat": 1, "group": "", "bucket": "loadout_bane", "category": "player",
		"blurb": "No wing secondaries roll or drop.",
		"mods": {"pool.block_slots": ["HARDPOINT_WING"]},
	},
	"no_modules": {
		"label": "No Modules", "threat": 2, "group": "", "bucket": "loadout_bane", "category": "player",
		"blurb": "No modules or shift-modes roll or drop.",
		"mods": {"pool.block_slots": ["MODULE", "SHIFT_MODE"]},
	},
	"no_starting_super": {
		"label": "No Starting Super", "threat": 1, "group": "", "bucket": "loadout_bane", "category": "player",
		"blurb": "You start without the smart-bomb super.",
		"mods": {"start.no_super": true},
	},
	"no_starting_mode": {
		"label": "No Starting Mode", "threat": 1, "group": "", "bucket": "loadout_bane", "category": "player",
		"blurb": "You start without a shift-mode.",
		"mods": {"start.no_mode": true},
	},

	# ── 4d. Player boons ─────────────────────────────────────────────────────
	"better_weapons": {
		"label": "Better Weapons", "threat": -2, "group": "weapon_damage", "bucket": "player_boon", "category": "player",
		"blurb": "Your weapon damage is boosted 50%.",
		"mods": {"player.weapon_damage_mult": 1.5},
	},
	"faster_weapons": {
		"label": "Faster Weapons", "threat": -2, "group": "", "bucket": "player_boon", "category": "player",
		"blurb": "Your rate of fire is boosted 50%.",
		"mods": {"player.fire_rate_mult": 1.5},
	},
	"better_modes": {
		"label": "Better Modes", "threat": -1, "group": "", "bucket": "player_boon", "category": "player",
		"blurb": "Shift-modes last 50% longer.",
		"mods": {"player.mode_duration_mult": 1.5},
	},
	"better_hull": {
		"label": "Better Hull", "threat": -2, "group": "", "bucket": "player_boon", "category": "player",
		"blurb": "Start with +3 hull pips.",
		"mods": {"player.hull_bonus": 3},
	},
	"better_shields": {
		"label": "Better Shields", "threat": -2, "group": "shield_strength", "bucket": "player_boon", "category": "player",
		"blurb": "Shields recharge sooner and faster.",
		"mods": {"player.shield_regen_delay_mult": 0.6, "player.shield_regen_rate_mult": 1.5},
	},
	"more_ammo": {
		"label": "More Ammo", "threat": -1, "group": "", "bucket": "player_boon", "category": "player",
		"blurb": "All ammo capacities are boosted 50%.",
		"mods": {"player.ammo_max_mult": 1.5},
	},
	"slow_enemies": {
		"label": "Slow Enemies", "threat": -2, "group": "enemy_speed", "bucket": "player_boon", "category": "enemy",
		"blurb": "Enemy ships move one speed rung slower.",
		"mods": {"enemy.rung_delta": -1},
	},
	"slow_bullets": {
		"label": "Slow Bullets", "threat": -2, "group": "bullet_speed", "bucket": "player_boon", "category": "enemy",
		"blurb": "Enemy fire travels one speed rung slower.",
		"mods": {"bullet.rung_delta": -1},
	},

	# ── 4e. Economy pairs (inverse boon ↔ bane, mutex by group) ───────────────
	# All economy numbers below are first-pass — tuner-bound (economy-sim §5).
	"galactic_tariffs": {
		"label": "Galactic Tariffs", "threat": 1, "group": "econ_buy_prices", "bucket": "economy_pair", "category": "economy",
		"blurb": "All outpost prices are 20% higher.",
		"mods": {"econ.shop_price_mult": 1.2},
	},
	"buyers_market": {
		"label": "Buyer's Market", "threat": -1, "group": "econ_buy_prices", "bucket": "economy_pair", "category": "economy",
		"blurb": "All outpost prices are 20% lower.",
		"mods": {"econ.shop_price_mult": 0.8},
	},
	"market_scarcity": {
		"label": "Market Scarcity", "threat": 1, "group": "econ_stock", "bucket": "economy_pair", "category": "economy",
		"blurb": "Outposts stock fewer offers.",
		"mods": {"econ.stock_delta": -1},
	},
	"market_surplus": {
		"label": "Market Surplus", "threat": -1, "group": "econ_stock", "bucket": "economy_pair", "category": "economy",
		"blurb": "Outposts stock more offers.",
		"mods": {"econ.stock_delta": 1},
	},
	"shoddy_imports": {
		"label": "Shoddy Imports", "threat": 1, "group": "econ_mk_quality", "bucket": "economy_pair", "category": "economy",
		"blurb": "Outpost gear rolls at lower Mk quality.",
		"mods": {"econ.mk_bias": -1},
	},
	"quality_goods": {
		"label": "Quality Goods", "threat": -1, "group": "econ_mk_quality", "bucket": "economy_pair", "category": "economy",
		"blurb": "Outpost gear rolls at higher Mk quality.",
		"mods": {"econ.mk_bias": 1},
	},
	"complex_upgrades": {
		"label": "Complex Upgrades", "threat": 1, "group": "econ_upgrade_mats", "bucket": "economy_pair", "category": "economy",
		"blurb": "Upgrades cost more materials.",
		"mods": {"econ.upgrade_mat_mult": 1.5},
	},
	"cheap_upgrades": {
		"label": "Cheap Upgrades", "threat": -1, "group": "econ_upgrade_mats", "bucket": "economy_pair", "category": "economy",
		"blurb": "Upgrades cost materials only.",
		"mods": {"econ.upgrade_no_bounty": true},
	},
	"costly_upgrades": {
		"label": "Costly Upgrades", "threat": 1, "group": "econ_upgrade_bounty", "bucket": "economy_pair", "category": "economy",
		"blurb": "Upgrades cost more bounty.",
		"mods": {"econ.upgrade_bounty_mult": 1.5},
	},
	"easy_upgrades": {
		"label": "Easy Upgrades", "threat": -1, "group": "econ_upgrade_bounty", "bucket": "economy_pair", "category": "economy",
		"blurb": "Upgrades cost bounty only.",
		"mods": {"econ.upgrade_no_mats": true},
	},
	"complex_repairs": {
		"label": "Complex Repairs", "threat": 1, "group": "econ_repair_mats", "bucket": "economy_pair", "category": "economy",
		"blurb": "Repairs also cost 1 material.",
		# Repairs cost no material at baseline (design §8), so a ×mult would be a no-op
		# ×0 — model the "adds material" bane as a flat material delta instead.
		"mods": {"econ.repair_mat_delta": 1},
	},
	"cheap_repairs": {
		"label": "Cheap Repairs", "threat": -1, "group": "econ_repair_mats", "bucket": "economy_pair", "category": "economy",
		"blurb": "Repairs cost 2 materials instead of bounty.",
		"mods": {"econ.repair_no_bounty": true, "econ.repair_mat_delta": 2},
	},
	"costly_repairs": {
		"label": "Costly Repairs", "threat": 1, "group": "econ_repair_bounty", "bucket": "economy_pair", "category": "economy",
		"blurb": "Repairs cost more bounty.",
		"mods": {"econ.repair_cost_mult": 1.5},
	},
	"easy_repairs": {
		"label": "Easy Repairs", "threat": -1, "group": "econ_repair_bounty", "bucket": "economy_pair", "category": "economy",
		"blurb": "Repairs cost bounty only.",
		# Baseline repairs already cost no material, so repair_no_mats is baseline-
		# equivalent until a baseline repair-material cost lands (design §8). Kept so
		# the pair is symmetric and future-proof.
		"mods": {"econ.repair_no_mats": true},
	},
	"costly_restock": {
		"label": "Costly Restock", "threat": 1, "group": "econ_restock", "bucket": "economy_pair", "category": "economy",
		"blurb": "Ammo and super restocks cost 50% more.",
		"mods": {"econ.restock_cost_mult": 1.5},
	},
	"cheap_restock": {
		"label": "Cheap Restock", "threat": -1, "group": "econ_restock", "bucket": "economy_pair", "category": "economy",
		"blurb": "Ammo and super restocks cost 30% less.",
		"mods": {"econ.restock_cost_mult": 0.7},
	},

	# ── 4f. Economy grants (bounty / material boons; flat effects) ────────────
	"salvage_rights": {
		"label": "Salvage Rights", "threat": -2, "group": "", "bucket": "grant", "category": "economy",
		"blurb": "Every combat clear grants materials; bosses grant more.",
		"mods": {"grant.level_clear_materials": 1, "grant.boss_clear_materials": 3},  # tuner-bound
	},
	"hazard_pay": {
		"label": "Hazard Pay", "threat": -2, "group": "", "bucket": "grant", "category": "economy",
		"blurb": "Clearing any combat node pays +100 bounty.",
		"mods": {"grant.node_clear_bounty": 100},  # tuner-bound
	},
	"starting_funds": {
		"label": "Starting Funds", "threat": -1, "group": "", "bucket": "grant", "category": "economy",
		"blurb": "Begin the patrol with 500 bounty.",
		"mods": {"grant.start_bounty": 500},  # tuner-bound
	},
	"mining_contract": {
		"label": "Mining Contract", "threat": -1, "group": "", "bucket": "grant", "category": "economy",
		"blurb": "Asteroids are worth 5 bounty each.",
		"mods": {"grant.asteroid_bounty": 5},  # tuner-bound
	},
	"ordnance_disposal": {
		"label": "Ordnance Disposal", "threat": -1, "group": "", "bucket": "grant", "category": "economy",
		"blurb": "Mines pay +5 bounty each.",
		"mods": {"grant.mine_bounty": 5},  # tuner-bound
	},
}


# --- Internal: resolve an id to its entry, warning + skipping unknowns ---
static func _entry(id: String) -> Dictionary:
	if CATALOG.has(id):
		return CATALOG[id]
	push_warning("Conditions: unknown condition id '%s' (skipped)" % id)
	return {}


# ── Aggregation API ──────────────────────────────────────────────────────────

# True if `id` is present in the active list.
static func has(active: Array, id: String) -> bool:
	return active.has(id)


# Product of all active `mods[key]` (multiplicative convention). Returns
# `default` when no active Condition sets the key.
static func scalar(active: Array, key: String, default: float = 1.0) -> float:
	var product := 1.0
	var found := false
	for id in active:
		var mods: Dictionary = _entry(id).get("mods", {})
		if mods.has(key):
			product *= float(mods[key])
			found = true
	return product if found else default


# Sum of all active `mods[key]` (additive convention). Returns 0.0 when none set it.
static func sum(active: Array, key: String) -> float:
	var total := 0.0
	for id in active:
		var mods: Dictionary = _entry(id).get("mods", {})
		if mods.has(key):
			total += float(mods[key])
	return total


# True if any active Condition sets `mods[key]` truthy (flag convention).
static func flag(active: Array, key: String) -> bool:
	for id in active:
		var mods: Dictionary = _entry(id).get("mods", {})
		if mods.has(key) and mods[key]:
			return true
	return false


# Union of all active list-valued `mods[key]` (list convention), deduped.
static func union(active: Array, key: String) -> Array:
	var out: Array = []
	for id in active:
		var mods: Dictionary = _entry(id).get("mods", {})
		if mods.has(key):
			for v in mods[key]:
				if not out.has(v):
					out.append(v)
	return out


# Signed sum of every active Condition's Threat.
static func net_threat(active: Array) -> int:
	var total := 0
	for id in active:
		total += int(_entry(id).get("threat", 0))
	return total


# Payout bonus multipliers, floored at 1.0 for a net-negative (all-boon) list.
static func bounty_mult(active: Array) -> float:
	return 1.0 + K_BOUNTY * maxf(0.0, float(net_threat(active)))


static func materials_mult(active: Array) -> float:
	return 1.0 + K_MATERIALS * maxf(0.0, float(net_threat(active)))


# False if any active Condition shares a nonempty mutex group with `id`.
static func mutex_ok(active: Array, id: String) -> bool:
	var grp: String = String(_entry(id).get("group", ""))
	if grp == "":
		return true
	for other in active:
		if other == id:
			continue
		if String(_entry(other).get("group", "")) == grp:
			return false
	return true


# Draw `count` distinct, mutex-respecting ids from the full CATALOG using a
# LOCAL RandomNumberGenerator seeded with `seed_value` (callers pass a
# decorrelated seed — this NEVER touches global randi/randf). Blocked draws are
# discarded; the pool shrinks each iteration so there's no infinite loop, and
# `count` is effectively clamped to what the mutex groups allow.
static func roll(count: int, seed_value: int) -> Array:
	var result: Array = []
	if count <= 0:
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = CATALOG.keys()
	var used_groups: Dictionary = {}
	while result.size() < count and not pool.is_empty():
		var i: int = rng.randi_range(0, pool.size() - 1)
		var id: String = pool[i]
		pool.remove_at(i)
		var grp: String = String(CATALOG[id].get("group", ""))
		if grp != "" and used_groups.has(grp):
			continue  # mutex-blocked; already removed from the pool
		result.append(id)
		if grp != "":
			used_groups[grp] = true
	return result


# Draw `bane_count` banes (threat > 0) THEN `boon_count` boons (threat < 0) from
# the CATALOG using a LOCAL RandomNumberGenerator seeded with `seed_value`. A
# SINGLE shared used-groups dict spans the whole combined pick, so an inverse pair
# (e.g. Fast Bullets ↔ Slow Bullets, both in `bullet_speed`) can never surface as
# bane + boon together. Same discipline as roll(): never touches global
# randi/randf, each pool shrinks per draw (no infinite loop), the counts are
# effectively clamped to what the mutex groups allow, and the result is
# deterministic per seed. Returns the banes first, then the boons.
static func roll_split(bane_count: int, boon_count: int, seed_value: int) -> Array:
	var result: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var used_groups: Dictionary = {}
	_draw_into(result, _pool_by_sign(true), bane_count, rng, used_groups)
	_draw_into(result, _pool_by_sign(false), boon_count, rng, used_groups)
	return result


# CATALOG ids whose Threat is > 0 (banes) when `positive`, else < 0 (boons),
# in CATALOG declaration order. (Threat == 0 ids belong to neither pool.)
static func _pool_by_sign(positive: bool) -> Array:
	var pool: Array = []
	for id in CATALOG.keys():
		var t: int = int(CATALOG[id].get("threat", 0))
		if (positive and t > 0) or (not positive and t < 0):
			pool.append(id)
	return pool


# Append up to `count` distinct, mutex-legal ids drawn from `pool` into `result`,
# sharing `used_groups` + `rng` with the rest of the split pick. `pool` is mutated
# (each draw is removed); a mutex-blocked draw is discarded and the loop retries
# from the shrunken pool, so `count` clamps to what the groups permit.
static func _draw_into(result: Array, pool: Array, count: int, rng: RandomNumberGenerator, used_groups: Dictionary) -> void:
	if count <= 0:
		return
	var drawn := 0
	while drawn < count and not pool.is_empty():
		var i: int = rng.randi_range(0, pool.size() - 1)
		var id: String = pool[i]
		pool.remove_at(i)
		var grp: String = String(CATALOG[id].get("group", ""))
		if grp != "" and used_groups.has(grp):
			continue  # mutex-blocked; already removed from the pool
		result.append(id)
		drawn += 1
		if grp != "":
			used_groups[grp] = true


# ── Display helpers ──────────────────────────────────────────────────────────
static func label(id: String) -> String:
	return String(_entry(id).get("label", id))


static func blurb(id: String) -> String:
	return String(_entry(id).get("blurb", ""))


static func threat_of(id: String) -> int:
	return int(_entry(id).get("threat", 0))


static func bucket(id: String) -> String:
	return String(_entry(id).get("bucket", ""))


# Picker category of `id` ("enemy"|"player"|"economy") — the front-end groups the
# customize picker into these three columns. (Orthogonal to bucket + threat sign.)
static func category_of(id: String) -> String:
	return String(_entry(id).get("category", ""))


# Mutex group of `id` ("" = ungrouped/stackable). Front-ends read this to
# live-enforce "one per group" on a curated pick.
static func group_of(id: String) -> String:
	return String(_entry(id).get("group", ""))


# ── Catalog integrity check (the test calls this) ────────────────────────────
# Returns a list of human-readable problems; empty == catalog is well-formed.
static func validate() -> Array:
	var problems: Array = []
	var seen_labels: Dictionary = {}
	var required := ["label", "blurb", "threat", "group", "bucket", "category", "mods"]
	for id in CATALOG.keys():
		var entry: Dictionary = CATALOG[id]
		for field in required:
			if not entry.has(field):
				problems.append("'%s' missing field '%s'" % [id, field])
		if entry.has("bucket") and not BUCKETS.has(entry["bucket"]):
			problems.append("'%s' has unknown bucket '%s'" % [id, String(entry["bucket"])])
		if entry.has("category") and not CATEGORIES.has(entry["category"]):
			problems.append("'%s' has unknown category '%s'" % [id, String(entry["category"])])
		if entry.has("mods") and not (entry["mods"] is Dictionary):
			problems.append("'%s' mods is not a Dictionary" % id)
		if entry.has("label"):
			var lbl: String = String(entry["label"])
			if seen_labels.has(lbl):
				problems.append("duplicate label '%s' (ids '%s' and '%s')" % [lbl, seen_labels[lbl], id])
			else:
				seen_labels[lbl] = id
	return problems
