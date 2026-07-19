extends Node

# Persistent run state. Autoloaded as "Run" so any scene can read/write.
# Survives scene changes; reset by new_run().

signal bounty_changed(value: int)
signal materials_changed(value: int)
signal hull_changed(cur: int, max: int)
signal shield_changed(cur: int, max: int)

# Currency
var bounty: int = 0:
	set(v):
		bounty = max(0, v)
		bounty_changed.emit(bounty)

# Materials — the salvage/upgrade currency (Roman 2026-06-14). Earned by scrapping spare
# items (1 per Mk) at the outpost, signal-event drops, and buying from the Junk Trader.
# Spent (with bounty) on in-place Mk upgrades. Distinct from the slotted Part *items* in
# loadout_snapshot / inventory / weapon_storage.
var materials: int = 0:
	set(v):
		materials = max(0, v)
		materials_changed.emit(materials)

# Ship persistence (set from Player when transitioning out of combat)
var current_hull: int = 0
# Super-weapon charges (Smart Bomb / Hyper / Phase Shift). Persists
# across scenes so a partial-spend in combat survives a trip to the
# outpost. Refilled to max by outpost's _on_super_refill action.
var super_charges: int = 0
var max_super_charges: int = 3
var max_hull: int = 0
var current_shield: int = 0
var max_shield: int = 0

# Loadout snapshot: dict of SlotType (int) -> Part resource
var loadout_snapshot: Dictionary = {}

# Passive Module bay (2026-06-13): a LIST of equipped ModulePart resources (up to
# MODULE_BAY_SIZE). Separate from the one-part-per-slot loadout_snapshot — modules are
# interchangeable, so a capped list fits better than scattered enum slots. The default
# Shield Core occupies one; dropping it frees a slot (glass cannon). The player applies
# this list at combat start. See docs/passive_module_bay_2026-06-13.md.
const MODULE_BAY_SIZE := 6
var modules: Array = []
# True once a module bay has been set up (new_run, or load-migration of an old save).
# Gates the glass-cannon state: only an EXPLICITLY-initialized bay with no Shield Core
# counts as shieldless — an un-initialized bay (old save / raw dev launch) stays shielded.
var bay_initialized: bool = false
const _ShieldCore = preload("res://scripts/parts/shield_core.gd")

# Uninstalled parts the player is carrying (cargo hold). Used by Junk Trader
# and any future inventory UI. Each entry is a Part resource. The Junk Trader
# refuses to operate when this is empty.
var inventory: Array = []

# Sector progress
var current_node_id: String = ""
var current_node_type: int = -1  # SectorNode.NodeType; -1 if none
# Active sector modifiers for the current combat. Set by the sector map when
# the player enters a node; cleared on new_run(). Values: "shielded",
# "armored", "heavily_armored", "aggressive", "wanted", "fleeing", "dangerous",
# "cruiser_support".
var sector_modifiers: Array = []
# Active Sector CONDITIONS for the current patrol (new system — Conditions catalog
# in scripts/systems/conditions.gd). Distinct from the legacy `sector_modifiers`
# above (per-POI kill-switched rolls): conditions are patrol-scoped, chosen/rolled
# up front, and aggregated declaratively via the Conditions helpers. Array of
# Condition id Strings. Reset in new_run(); persisted via _SAVE_FIELDS.
var active_conditions: Array = []
# When current_node_type is HAZARD, this picks which hazard played out:
#   "minefield" or "asteroid_field". Set by sector_map._on_node_pressed.
var current_hazard_subtype: String = ""
# When true, level "complete" should send the player back to the main menu
# (not the sector map). Set by Test Hazard / future test launchers from the
# main menu. Cleared automatically when consumed.
var test_mode_active: bool = false
# Bonus bounty per asteroid kill on the next asteroid_field run. Set by
# Freespace Miner signal event so the player gets paid for cracking them.
# Cleared by main.gd after consumption.
var asteroid_bonus_bounty: int = 0
# Bonus bounty per mine cleared on minefield runs. Mirrors asteroid_bonus_bounty
# (event seam, additive) — the Ordnance Disposal Condition stacks its own grant
# on top (grant.mine_bounty) at the mine death sites. Reset in new_run().
var mine_bonus_bounty: int = 0
# Optional special intro for the next combat level. "fly_up_from_below" is
# the Ambush intro (fighters parallax-up before attacking). Empty = default.
# Cleared by main.gd after consumption.
var combat_intro: String = ""
# Dev: force the next boss spawn to use a specific scene path. Set by the
# Dev Menu "Boss Fight" picker. Cleared by wave_generator after consumption.
var forced_boss_scene: String = ""
# Stellar metadata of the sector node the player just clicked. Read by
# combat / hazard scenes to seed the galaxy_backdrop with a consistent
# planet + nebula tint. Keys: planet_idx (int), nebula_band (String),
# nebula_tint (Color), star_color (Color), star_distance_ratio (float 0=close 1=far).
# Empty until the first node click.
var current_stellar: Dictionary = {}
# Machinegun ammo balance — persists across scenes so refills at outposts
# carry into the next combat. 0 = empty; -1 = no MG equipped (default).
var ammo: int = -1
# Secondary-weapon ammo balance (Rocket Pod / Seeking Missile). Same
# convention as `ammo`: 0 = empty, -1 = no ammo-bearing secondary
# equipped. Persists across scenes; the secondary Part's apply() seeds
# from this on equip so a refill at outpost A carries into outpost B.
var secondary_ammo: int = -1
# Max capacity for the equipped secondary so the upcoming shop refill UI
# can clamp / display % remaining. -1 mirrors `secondary_ammo == -1`.
var secondary_ammo_max: int = -1
# Set of enemy scene paths the player has encountered (i.e. seen
# spawned in a wave). Persists across sessions via JSON in the codex
# save file. Used by the Enemy Codex on the main menu.
var encountered_enemies: Dictionary = {}
var visited_nodes: Array = []  # node ids
var sectors_cleared: int = 0
# Run-wide count of bosses defeated this run. Each defeated boss grants
# +5% max HP to every SUBSEQUENT boss spawned (boss_base._ready applies the
# scale: max_health *= 1 + 0.05 * bosses_defeated). Cumulative across all
# sectors; reset only by new_run(). Incremented exactly once per boss in
# boss_base.explode() (guarded by the boss's _dying flag).
var bosses_defeated: int = 0
var used_boss_scenes: Array = []  # scene paths used in prior sectors; prevents cross-sector repeats
# Outpost-as-persistent-hub state (Roman 2026-06-08). The outpost is reached from a
# sector-map button (not a POI); its stock + service charges persist across visits and
# REFRESH on boss kill (re-roll stock + +1d6 to each charge pool). Repair/ammo are
# charge-limited: 2d6 each at run start, consumed per use. Charges + refresh flag are
# saved; the rolled offers are in-memory only (re-roll on app restart — cheap).
var repair_charges: int = 0
var ammo_restock_charges: int = 0
var outpost_needs_refresh: bool = false
var outpost_weapon_offers: Array = []   # [{part, cost, sold}] — in-memory, set by outpost
var outpost_upgrade_offers: Array = []  # [{key, name, desc, next_mk, cost, sold}]
# Combat nodes (non-boss, non-hazard) completed since the start of the
# current sector. Drives wave_generator scaling. Resets to 0 when a new
# sector begins (endless mode).
var combats_in_sector: int = 0

# Stats
var enemies_killed: int = 0
var max_bounty_earned: int = 0
var run_distance: float = 0.0
# Run-summary stats (Phase 1 — docs/run_summary_scope_2026-06-01.md). Cheap Tier-1
# tallies + an active-combat run timer. run_stats keys grow in Phase 2.
var run_time_seconds: float = 0.0
var run_stats: Dictionary = {}

# Random seed for reproducible runs (sector map + shop rolls).
var run_seed: int = 0
# True when the current run's run_seed came from a player-entered custom seed
# (via patrol_start's seed box), false when it was randomly rolled. Surfaced on
# the run summary + history record. Set both ways in new_run(); persisted via
# _SAVE_FIELDS so a resumed run keeps the "(custom)" tag.
var seed_was_custom: bool = false

# ---- Ship choice (per-patrol; picked in the ship-select modal at new-patrol start) ----
# ship_variant: index into ShipCatalog.SHIPS (0 = the default Starblaster; the full roster +
# scene paths live in scripts/strings/ship_catalog.gd). Selects which player scene combat
# instantiates. livery_color: the player-chosen hull livery tint; only honored when
# livery_chosen is true, otherwise player.gd falls back to its run_seed-derived random tint.
var ship_variant: int = 0
var livery_color: Color = Color(1.0, 0.0, 0.0)
var livery_chosen: bool = false

const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")


# Scene path for the chosen player ship variant (clamped to the known set).
func player_scene_path() -> String:
	return ShipCatalog.scene_path(ship_variant)

# ---- Persistent upgrades (outpost purchases) --------------------------
# Mk 0..9 per category. Applied to the player at combat start via
# player.apply_run_upgrades(). Increasing the Mk is the only path the
# player has to grow these stats — basic parts no longer add hull/shield.
var hull_mk: int = 0
var armor_mk: int = 0           # RETIRED — kept for save compat
var thrusters_mk: int = 0
var self_repair_mk: int = 0     # RETIRED 2026-06-13 (→ Repair Nanites module) — save compat only
var shield_cap_mk: int = 0
var shield_recharge_mk: int = 0 # RETIRED — kept for save compat
var hull_plating_mk: int = 0    # RETIRED 2026-06-13 (→ Ablative Plating module) — save compat only

# Stored cannons swapped out at outposts (the new one takes the CANNON
# slot, the old one moves here). Each entry is a Part resource.
var weapon_storage: Array = []

# ---- Active primary cannon (single-active model, Roman 2026-06-11) -----
# The ship carries ONE active primary. cannon_pool is kept as a 1-element
# array ([active]) with active_cannon_idx always 0 — the shape many readers
# (HUD, outpost, run_save) still expect — but there is NO multi-cannon pool
# and NO Q-cycle anymore. Equipping a new primary sends the current one to the
# sellable hold (`weapon_storage`), exactly like secondaries (_equip_primary).
# A cannon is INFINITE when ammo_at_mark() returns -1 (Energy Blaster + the
# blaster-replacements Heavy/Twin); metered cannons carry ammo and, when a
# NON-regen one runs dry, revert to an owned blaster (revert_to_blaster).
# `loadout_snapshot[CANNON]` mirrors cannon_pool[0].
var cannon_pool: Array = []
var active_cannon_idx: int = 0

# Sector Map V3 cache. Single source of truth for the current sector's
# 3-row layout: every POI + per-row boss with completion flags. Generated
# once on sector entry via start_new_sector(); persists across the
# combat / outpost round-trips so the map renders identically on return.
#
# Shape:
#   {
#     "sector_idx": int,
#     "seed": int,
#     "rows": [                           # exactly 3
#       {
#         "anchor": Vector2,              # star/route anchor (for drawing)
#         "boss": {
#           "id": "s1_r0_boss",
#           "node_type": int,             # SectorNode.NodeType.BOSS (3)
#           "pos": Vector2,
#           "boss_scene": String,         # path passed to forced_boss_scene
#           "completed": bool,
#         },
#         "pois": [                       # ordered along the route, left→right
#           {
#             "id": "s1_r0_p0",
#             "node_type": int,           # COMBAT/OUTPOST/SIGNAL/HAZARD enum
#             "hazard_subtype": String,   # "" unless node_type == HAZARD
#             "pos": Vector2,
#             "completed": bool,
#           }, ...
#         ],
#       }, ...
#     ],
#   }
var sector_map_cache: Dictionary = {}

func _ready() -> void:
	# Cheap fresh seed on startup; will be overwritten by new_run()
	run_seed = randi()
	_load_codex()
	# Seed defaults so Hangar / dev tools that open the Manage Ship modal
	# (or read loadout_snapshot) without going through new_run() still see
	# the starter Energy Blaster + Smart Bomb. Idempotent — new_run() will
	# call this again on a real run start.
	_seed_default_loadout_snapshot()
	_assert_save_surface_synced()


# ---- Enemy Codex persistence ------------------------------------------
const CODEX_SAVE_PATH := "user://enemy_codex.json"

func mark_encountered(scene_path: String) -> void:
	if scene_path == "" or encountered_enemies.has(scene_path):
		return
	encountered_enemies[scene_path] = true
	_save_codex()


func _save_codex() -> void:
	var f := FileAccess.open(CODEX_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(encountered_enemies.keys()))


func _load_codex() -> void:
	if not FileAccess.file_exists(CODEX_SAVE_PATH):
		return
	var f := FileAccess.open(CODEX_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		for p in parsed:
			encountered_enemies[String(p)] = true


# ---- Run history persistence ------------------------------------------
# Dated index of past runs (separate JSON channel from the .tres resume save).
# Uses only already-accumulated Run stats — no new instrumentation.
const HISTORY_SAVE_PATH := "user://run_history.json"
const HISTORY_MAX_ENTRIES := 50

# Append a record of the just-ended run. Call on run-end (death now; victory when
# that path exists) BEFORE new_run() resets the stats.
func record_run_history(outcome: String) -> void:
	var record := {
		"date": Time.get_datetime_string_from_system(false, true),
		"outcome": outcome,
		"kills": int(enemies_killed),
		"boss_kills": int(bosses_defeated),
		"sectors": int(sectors_cleared),
		"bounty": int(max_bounty_earned),
		"distance": int(run_distance),
		"seed": int(run_seed),
		"seed_custom": bool(seed_was_custom),
		# Run-summary Phase 1 stats (so the history detail can surface them).
		"time": int(run_time_seconds),
		"bounty_gained": int(run_stats.get("bounty_gained", 0)),
		"bounty_spent": int(run_stats.get("bounty_spent", 0)),
		"damage_shield": int(run_stats.get("damage_shield", 0)),
		"damage_hull": int(run_stats.get("damage_hull", 0)),
		"asteroids": int(run_stats.get("asteroids", 0)),
		"mines_cleared": int(run_stats.get("mines_cleared", 0)),
		# Phase 2 stats.
		"shots_fired": int(run_stats.get("shots_fired", 0)),
		"shots_hit": int(run_stats.get("shots_hit", 0)),
		"locations_visited": int(run_stats.get("locations_visited", 0)),
		"stations_visited": int(run_stats.get("stations_visited", 0)),
		"signals_visited": int(run_stats.get("signals_visited", 0)),
		"weapons_used": int((run_stats.get("weapons_used", {}) as Dictionary).size()),
	}
	var hist: Array = load_run_history()
	hist.append(record)
	# Cap to the most recent N so the file can't grow without bound.
	if hist.size() > HISTORY_MAX_ENTRIES:
		hist = hist.slice(hist.size() - HISTORY_MAX_ENTRIES, hist.size())
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(hist))


func load_run_history() -> Array:
	if not FileAccess.file_exists(HISTORY_SAVE_PATH):
		return []
	var f := FileAccess.open(HISTORY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		return parsed
	return []

# ── Sector modifier query helpers ──────────────────────────────────────────
# Single seam for asking "is modifier X active on the current combat?". Any
# gameplay site (enemy stat tweak, spawn-chance hook, payout, etc.) should
# route through here rather than poking sector_modifiers directly so the
# storage representation can change without touching call sites.
func has_modifier(id: String) -> bool:
	return sector_modifiers.has(id)


# ── Sector CONDITION query helpers (new system) ─────────────────────────────
# Thin delegates so gameplay sites route their Condition queries through Run
# with `active_conditions` — the aggregation logic lives in Conditions (SSOT).
func has_condition(id: String) -> bool:
	return Conditions.has(active_conditions, id)

func cond_scalar(key: String, default: float = 1.0) -> float:
	return Conditions.scalar(active_conditions, key, default)

func cond_sum(key: String) -> float:
	return Conditions.sum(active_conditions, key)

func cond_flag(key: String) -> bool:
	return Conditions.flag(active_conditions, key)

func cond_union(key: String) -> Array:
	return Conditions.union(active_conditions, key)

func condition_bounty_mult() -> float:
	return Conditions.bounty_mult(active_conditions)

func condition_materials_mult() -> float:
	return Conditions.materials_mult(active_conditions)

func condition_net_threat() -> int:
	return Conditions.net_threat(active_conditions)


# ── Single pipe entry: install a set of active Conditions on the run ─────────
# Every front-end (Wildcard now; Curated / Threat-Level later) funnels its
# chosen ids through here so the install order + one-time grants live in ONE
# place. Call AFTER new_run() and after any run-settings writes (new_run resets
# active_conditions to [] and re-seeds the loadout snapshot with EMPTY
# conditions, so the start-gate flags below only take effect once we install
# here and re-seed).
#
# NOT idempotent: it awards start_bounty, so calling it twice would double-grant
# the flat bounty. Front-ends must call it EXACTLY ONCE per run.
func apply_conditions(ids: Array) -> void:
	active_conditions = ids.duplicate()
	# Re-seed the loadout snapshot so start.no_super / start.no_mode gates in
	# _seed_default_loadout_snapshot fire against the just-installed conditions.
	# The seed only ADDS slots (never removes), so clear the snapshot first —
	# otherwise a stale super/mode entry from the new_run seed would survive.
	loadout_snapshot = {}
	_seed_default_loadout_snapshot()
	# Starting Funds grant: award through award_bounty so the net-Threat bounty
	# multiplier folds over the flat grant (same accepted grant-then-mult
	# stacking as Hazard Pay — the grant carries −Threat, so with an all-boon
	# list the mult floors at 1.0 and the grant lands flat).
	var start_bounty := int(cond_sum("grant.start_bounty"))
	if start_bounty > 0:
		award_bounty(start_bounty)


# Multiplier applied to ANY rare cruiser-encounter roll while the
# "cruiser_support" sector modifier is active. Returns 1.0 (no-op) otherwise.
# Reusable seam: future cruiser-flavored encounters (escort packs, cruiser
# duos, cruiser-led waves, etc.) should multiply their own base spawn chance
# by this so the one modifier governs them all from a single knob.
const CRUISER_SUPPORT_CHANCE_MULT: float = 2.75

func cruiser_encounter_chance_mult() -> float:
	# New Conditions system (Heavy Escort) reads through the generic aggregator;
	# the legacy per-POI modifier stays as a floor (always-false while kill-switched).
	var m := cond_scalar("cruiser.encounter_mult", 1.0)
	if has_modifier("cruiser_support"):
		m = maxf(m, CRUISER_SUPPORT_CHANCE_MULT)
	return m


# seed_override: when non-zero, forces run_seed to that value (a player-entered
# custom seed) instead of randi(), so the whole run reproduces. 0 = "no override"
# = random roll. RESERVED-0 EDGE: a player who literally types "0" resolves (via
# parse_seed) to 0 and therefore gets a RANDOM run, not a seed-0 run — an accepted
# corner case (0 doubles as the sentinel). Everything downstream (outpost 2d6
# charge rolls, blind-condition split, sector gen, node factions) derives from
# run_seed, so setting it here — at the SAME early point randi() used to land —
# keeps the entire run reproducible from the custom seed.
func new_run(seed_override: int = 0) -> void:
	# Starting fresh — invalidate any saved run so Resume Patrol on the main
	# menu can't drop the player back into the old state if they bail before
	# the first sector map entry rewrites the save.
	clear_save()
	# Dev faction override is one-run-scoped — clear it so a real New Game never
	# inherits a forced faction from a prior dev session (the dev launcher re-sets
	# it AFTER calling new_run). active_faction is per-level, also cleared.
	remove_meta("forced_faction")
	remove_meta("forced_faction_once")  # one-shot signal-event faction force (corpo inspection, etc.)
	remove_meta("active_faction")
	remove_meta("force_all_signal")  # dev all-signal-sector flag (re-set after new_run by the launcher)
	bounty = 0
	materials = 0
	enemies_killed = 0
	max_bounty_earned = 0
	run_distance = 0.0
	run_time_seconds = 0.0
	run_stats = {"damage_shield": 0, "damage_hull": 0, "bounty_gained": 0, "asteroids": 0,
		"bounty_spent": 0, "mines_cleared": 0, "materials_gained": 0, "materials_spent": 0,
		# Phase 2 (run_summary_scope_2026-06-01): per-projectile shots + node visits.
		# accuracy = shots_hit / shots_fired at display time (pierce/AoE can exceed 100%).
		"shots_fired": 0, "shots_hit": 0,
		"locations_visited": 0, "stations_visited": 0, "signals_visited": 0,
		# weapons_used is a set (name → true); .size() = unique primaries fielded this run.
		"weapons_used": {}}
	sectors_cleared = 0
	bosses_defeated = 0
	combats_in_sector = 0
	# run_seed drives the run's generated state — set it FIRST so the outpost-charge rolls below
	# derive from it (randi() is the only intentionally-random source; everything else keys off
	# run_seed for seed-consistent runs). A non-zero seed_override substitutes a player-entered
	# custom seed here so the charges + all downstream generation reproduce from it.
	if seed_override != 0:
		run_seed = seed_override
		seed_was_custom = true
	else:
		run_seed = randi()
		seed_was_custom = false
	# Outpost hub: seed 2d6 repair + 2d6 ammo-restock charges; stock rolls on first visit.
	repair_charges = _roll_dice(2, 6, 0)
	ammo_restock_charges = _roll_dice(2, 6, 1)
	outpost_needs_refresh = false
	outpost_weapon_offers = []
	outpost_upgrade_offers = []
	visited_nodes = []
	used_boss_scenes = []
	current_node_id = ""
	# Per-node combat context — saved fields (_SAVE_FIELDS) that the sector map rewrites on
	# each node entry, but new_run() must clear them too: a New Game started right after a
	# prior run could otherwise read a stale node type / hazard / stellar / bonus on its first
	# frame before the map overwrites them. forced_boss_scene is a dev/boss-POI handoff that
	# wave_generator consumes; clearing it here stops a leftover pick leaking into a fresh run.
	# (Health audit 2026-06-15.)
	current_node_type = -1
	current_hazard_subtype = ""
	current_stellar = {}
	asteroid_bonus_bounty = 0
	mine_bonus_bounty = 0
	combat_intro = ""
	forced_boss_scene = ""
	sector_modifiers = []
	active_conditions = []
	loadout_snapshot = {}
	inventory = []
	current_hull = 3
	max_hull = 3
	current_shield = 10
	max_shield = 10
	hull_mk = 0
	armor_mk = 0
	thrusters_mk = 0
	self_repair_mk = 0
	shield_cap_mk = 0
	shield_recharge_mk = 0
	hull_plating_mk = 0
	weapon_storage = []
	cannon_pool = []
	active_cannon_idx = 0
	sector_map_cache = {}
	# Reset ammo state — Part.apply() reseeds on equip.
	ammo = -1
	secondary_ammo = -1
	secondary_ammo_max = -1
	# Ship choice resets to default A / unchosen livery; the ship-select modal re-sets these
	# AFTER new_run() (same post-new_run pattern as the dev forced_faction override).
	ship_variant = 0
	livery_color = Color(1.0, 0.0, 0.0)
	livery_chosen = false
	# Reset super-weapon state — player._ready will repopulate via the
	# equipped Smart Bomb's apply(). Seeded below so meta-scene reads
	# (Manage Ship modal, outpost status bar) match what combat will apply.
	super_charges = 0
	max_super_charges = 3
	# Seed the ship starting kit (2026-07-11: per-ship, from ShipCatalog `loadout`) so meta
	# scenes see the same loadout combat will apply. new_run resets ship_variant to 0 above —
	# a front-end that picks a different hull (patrol_start) writes ship_variant AFTER this
	# and must call reseed_loadout_for_ship(). The seeder also owns the module bay now
	# (the old unconditional `modules = [ShieldCore]` seed folded in).
	bay_initialized = true
	_seed_default_loadout_snapshot()


# ---- Module bay helpers (the LIST-backed passive bay) -----------------------
func has_module(mod_id: String) -> bool:
	for m in modules:
		if m != null and "module_id" in m and String(m.module_id) == mod_id:
			return true
	return false


# Hull-repair discount from the module bay (Reinforced Hull Mk.9 = 30%). Best wins.
# Read by outpost._hull_repair_cost — repairs happen at the outpost, so the discount
# never routes through the player ship.
func hull_repair_discount() -> float:
	var best := 0.0
	for m in modules:
		if m != null and m.has_method("repair_discount"):
			best = maxf(best, float(m.repair_discount()))
	return best


# Append a module if there's room (≤ MODULE_BAY_SIZE). Returns false if full/null.
func add_module(part) -> bool:
	if part == null or modules.size() >= MODULE_BAY_SIZE:
		return false
	modules.append(part)
	return true


# Remove + return the module at idx (or null). Caller decides where it goes (sold/cargo).
func remove_module(idx: int):
	if idx >= 0 and idx < modules.size():
		var m = modules[idx]
		modules.remove_at(idx)
		return m
	return null


# Roll N dice of S sides (e.g. _roll_dice(2,6,salt) = 2d6), DETERMINISTIC: keyed on run_seed +
# salt so a replayed seed yields the same outpost charges. Each distinct economy roll passes a
# distinct salt (boss-refresh rolls fold in bosses_defeated). (Health audit 2026-06-16 — was
# global randi; outpost charges are now part of seed-consistent runs.)
func _roll_dice(n: int, sides: int, salt: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = (run_seed * 2654435761) ^ (salt * 40503) ^ 0xD1CE
	var total: int = 0
	for _i in n:
		total += 1 + (rng.randi() % sides)
	return total


# Called when a boss is defeated (from boss_base.explode). Bumps the run-wide boss
# count AND refreshes the outpost: +1d6 to each service-charge pool and flags the
# stock to re-roll on the next visit (boss-gated shop progression, Roman 2026-06-08).
func on_boss_defeated() -> void:
	bosses_defeated += 1
	repair_charges += _roll_dice(1, 6, 1000 + bosses_defeated)
	ammo_restock_charges += _roll_dice(1, 6, 2000 + bosses_defeated)
	outpost_needs_refresh = true


func record_kill(value: int) -> int:
	enemies_killed += 1
	return award_bounty(value)


# Bounty award choke-point: applies the Condition bounty multiplier, adds to
# bounty, tallies the bounty-gained run stat, returns the AWARDED amount (what
# actually landed). All combat bounty grants (kills, hazard clears, node/grant
# payouts) route through here so the Condition multiplier is applied exactly
# once and callers can mirror Run's number (e.g. main.gd's local HUD bounty).
# Outpost/shop refunds are not "awards" — they don't come through here.
func award_bounty(amount: int) -> int:
	var awarded := maxi(0, roundi(amount * condition_bounty_mult()))
	bounty += awarded
	if bounty > max_bounty_earned:
		max_bounty_earned = bounty
	stat_add("bounty_gained", awarded)
	return awarded


# Materials award choke-point for COMBAT drops/grants only: applies the
# Condition materials multiplier, routes through add_materials (which tallies
# materials_gained), returns the AWARDED amount. Outpost scrap keeps calling
# raw add_materials — the multiplier is for combat drops/grants (design §5).
func award_combat_materials(amount: int) -> int:
	var awarded := maxi(0, roundi(amount * condition_materials_mult()))
	add_materials(awarded)
	return awarded


# Run-summary stat accumulator (Phase 1). Additive into run_stats; missing keys seed 0.
func stat_add(key: String, n: int) -> void:
	run_stats[key] = int(run_stats.get(key, 0)) + n


# Phase 2: record a primary cannon as "used" this run (set-add; idempotent).
# run_stats["weapons_used"].size() is the unique-weapons count.
func note_weapon_used(weapon_name: String) -> void:
	if weapon_name == "":
		return
	var used: Dictionary = run_stats.get("weapons_used", {})
	used[weapon_name] = true
	run_stats["weapons_used"] = used


# Bounty-spend choke-point (Phase 2): subtract bounty AND tally what was spent.
# All outpost/shop/event purchases route through here so "bounty spent" is exact.
func spend_bounty(amount: int) -> void:
	bounty -= amount           # setter fires bounty_changed
	stat_add("bounty_spent", amount)


# Materials earn/spend choke-points (mirror bounty). add_materials: scrap payouts + signal
# drops + Junk Trader buys. spend_materials: Mk upgrades + Junk Trader sells.
func add_materials(amount: int) -> void:
	if amount <= 0:
		return
	materials += amount        # setter fires materials_changed
	stat_add("materials_gained", amount)


func spend_materials(amount: int) -> void:
	if amount <= 0:
		return
	materials -= amount        # setter fires materials_changed
	stat_add("materials_spent", amount)

func mark_node_visited(node_id: String) -> void:
	if not visited_nodes.has(node_id):
		visited_nodes.append(node_id)
	current_node_id = node_id

func sector_complete() -> void:
	sectors_cleared += 1


# ---- Sector Map V3 helpers --------------------------------------------
# The cache is owned here so combat/outpost/signal scenes can mark nodes
# completed without touching the map scene. See `sector_map_cache` doc
# above for the shape.

const SectorNodeType = preload("res://scripts/systems/sector_node.gd").NodeType
const SectorNameGenerator = preload("res://scripts/strings/sector_name_generator.gd")

# Total sectors required to beat the game. A run is now ONE sector of 3 rows
# (= 3 bosses); clearing it is victory ("PATROL COMPLETE"). Drives the "Sector
# Patrol X/Y" header in sector_map_v3 + the victory gate in cleared_summary.
# Designer-tunable — bump for a multi-sector / endless mode (boss HP escalation
# already supports boss 4+ via boss_base.BOSS_HP_MULT[3]). Read by sector_map_v3.
const TOTAL_SECTORS: int = 1

# Full rollable modifier vocabulary. Most effects live in
# scripts/levels/director.gd::_apply_sector_modifiers (per-enemy stat tweaks).
# A few are handled at their own gameplay site instead and intentionally have
# NO match-case in the director:
#   "dangerous"        -> scripts/player.gd::take_damage (2x incoming damage)
#   "cruiser_support"  -> scripts/main.gd::_maybe_schedule_rare_cruiser
#                         (boosts rare cruiser encounter chance; see
#                          Run.cruiser_encounter_chance_mult)
# When adding a modifier, register it here and implement its effect either in
# the director or at a dedicated site (and note it above).
# ============================================================================
# SECTOR MODIFIERS — DISABLED, FLAGGED FOR RE-EVAL (Roman 2026-06-10).
# Pulled from rolling AND application pending a redesign pass. Flip this flag to
# re-enable the whole system: POI generation (_gen_row_pois), the node-entry
# assignment (sector_map_v3 -> Run.sector_modifiers), and through them every
# downstream effect (director._apply_sector_modifiers per-enemy tweaks, the
# player's "dangerous" 2x damage, cruiser_support encounter boost, the outpost
# modifier readout). The vocabulary + effect wiring below is intentionally kept.
# ============================================================================
const SECTOR_MODIFIERS_ENABLED: bool = false

const ALL_SECTOR_MODIFIERS := [
	"wanted", "armored", "heavily_armored", "shielded",
	"aggressive", "dangerous", "fleeing", "cruiser_support",
]

# Per-POI chance to carry no modifier. Designer-tunable knob; ~40% null keeps
# the map from feeling uniformly modified at high sector counts. Flagged as
# guessed default — surface in tuner if it matters.
const POI_NULL_MODIFIER_CHANCE: float = 0.4

# Outpost-density rules. Designer (Cody 2026-05-24): "2-3 per sector, rarely 1
# or 4, super rarely 0." Two unified constraints enforced together by
# _enforce_outpost_rules (Roman 2026-06-02 — the per-row cap is the recurring
# "multiple stations in one row" fix):
#   1. PER ROW (each star system): at most OUTPOST_MAX_PER_ROW outposts.
#   2. PER SECTOR (all 3 rows): total in [OUTPOST_MIN_PER_SECTOR, OUTPOST_MAX_PER_SECTOR].
# With 3 rows × max 1/row the sector total can never exceed 3, so the per-sector
# MAX is effectively a safety rail; the MIN drives promotion. Promotion only
# targets rows that have NO outpost yet, so it can never re-introduce a duplicate.
const OUTPOST_MAX_PER_ROW: int = 1
const OUTPOST_MIN_PER_SECTOR: int = 2
const OUTPOST_MAX_PER_SECTOR: int = 4

# (Re)generate the sector map cache for the given sector index + seed.
# Always overwrites; call when entering a fresh sector.
func start_new_sector(sector_idx: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Roll sector-wide modifier pool: 1 base + 1 per prior sector clear, capped 6.
	# At sector 1 with 0 cleared, pool = 1. Sector 6+ with 5+ cleared, pool = 6.
	var modifier_count: int = clampi(1 + sectors_cleared, 1, 6)
	var sector_mod_pool: Array = _pick_sector_modifiers(rng, modifier_count)
	var rows: Array = []
	# Three rows, anchored at the same Y-coords the V3 map renders at.
	var anchors := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]
	var boss_positions := [Vector2(448, 64), Vector2(448, 128), Vector2(448, 192)]
	# Boss roster for this sector's 3 rows: 3 of all 7 bosses, drawn at random
	# with conflict-pair + no-repeat rules (see _pick_row_bosses).
	var boss_scenes: Array = _pick_row_bosses(sector_idx, rng, used_boss_scenes)
	for r in range(3):
		var pois: Array = _gen_row_pois(rng, sector_idx, r, anchors[r], sector_mod_pool)
		var boss := {
			"id": "s%d_r%d_boss" % [sector_idx, r],
			"node_type": int(SectorNodeType.BOSS),
			"pos": boss_positions[r],
			"boss_scene": boss_scenes[r],
			"completed": false,
			# Bosses currently carry no modifiers — only POIs do. Open issue:
			# decide whether row bosses inherit the row's modifier theme.
			"modifiers": [],
		}
		rows.append({
			"anchor": anchors[r],
			"boss": boss,
			"pois": pois,
		})
	# (Outpost POI rules removed 2026-06-08 — outposts are a sector-map hub button,
	# not POIs, so the per-row cap + min-promotion no longer apply.)
	# STRONGHOLD promotion (2026-07-18, stronghold-assault go-live): convert eligible COMBAT POIs on
	# ASTEROID POIs (deco obj_kind = large_asteroid/cluster — the same deterministic roll the map +
	# stellar authoring derive from hash(id)^run_seed, so the node always sits on asteroid scenery)
	# into Stronghold Attack nodes. Caps: ≤ STRONGHOLD_MAX_PER_ROW per system line, ≤
	# STRONGHOLD_MAX_PER_SECTOR total. Decorrelated rng (seed ^ salt) so the promotion never shifts
	# positions/bosses/subtypes rolled above. Faction carries over (a stronghold IS faction combat).
	_promote_stronghold_pois(rows, seed_value)
	# sector_modifiers (for the outpost display) = the DISTINCT modifiers actually present on the
	# sector's POIs, so the readout matches what the player will encounter.
	var active_mods: Array = []
	for row in rows:
		for poi in row.get("pois", []):
			for m in poi.get("modifiers", []):
				if not active_mods.has(m):
					active_mods.append(m)
	sector_map_cache = {
		"sector_idx": sector_idx,
		"seed": seed_value,
		"sector_name": SectorNameGenerator.generate(seed_value),
		# Outpost name — generated once per sector (decorrelated seed), persists across all visits
		# via the cache (Roman 2026-06-15). Reuses the sector name generator's station-flavored pools.
		"outpost_name": SectorNameGenerator.generate(int(seed_value) ^ 0x9E3779B9),
		"sector_modifiers": active_mods,
		"rows": rows,
	}
	for bs in boss_scenes:
		if bs != BOSS_CONDUCTOR and not used_boss_scenes.has(bs):
			used_boss_scenes.append(bs)


# Picks `count` distinct modifiers from ALL_SECTOR_MODIFIERS. Count is clamped
# to the available vocabulary so a future cap > vocab won't infinite-loop.
func _pick_sector_modifiers(rng: RandomNumberGenerator, count: int) -> Array:
	var pool: Array = ALL_SECTOR_MODIFIERS.duplicate()
	var n: int = clampi(count, 0, pool.size())
	var picks: Array = []
	for i in range(n):
		var idx: int = rng.randi() % pool.size()
		picks.append(pool[idx])
		pool.remove_at(idx)
	return picks


# Unified outpost rules, applied to the assembled `rows` array so every
# conversion lands in the cache. Two passes, in order:
#   1. PER-ROW CAP — within each row, demote all but OUTPOST_MAX_PER_ROW outposts
#      back to COMBAT. This is the fix for "multiple stations in one row": the
#      per-POI type roll in _gen_row_pois has no row awareness, so a row can roll
#      OUTPOST 2-3 times; here we keep one (random) and convert the rest.
#   2. PER-SECTOR COUNT — clamp the surviving sector total into
#      [OUTPOST_MIN_PER_SECTOR, OUTPOST_MAX_PER_SECTOR]. Underflow promotes a
#      random COMBAT, but ONLY in a row that has no outpost yet, so promotion can
#      never re-create a duplicate. Overflow (only reachable if MAX < #rows)
#      demotes a random outpost.
# Conversion preserves position + id, only rewrites node_type (and clears
# hazard_subtype when promoting, though we only convert COMBAT↔OUTPOST here).
func _enforce_outpost_rules(rows: Array, rng: RandomNumberGenerator) -> void:
	# Pass 1 — per-row cap.
	for row in rows:
		var row_outposts: Array = []
		for poi in row.pois:
			if int(poi.node_type) == int(SectorNodeType.OUTPOST):
				row_outposts.append(poi)
		while row_outposts.size() > OUTPOST_MAX_PER_ROW:
			var idx: int = rng.randi() % row_outposts.size()
			var victim = row_outposts[idx]
			row_outposts.remove_at(idx)
			victim.node_type = int(SectorNodeType.COMBAT)

	# Pass 2 — per-sector count clamp.
	var outposts: Array = []
	for row in rows:
		for poi in row.pois:
			if int(poi.node_type) == int(SectorNodeType.OUTPOST):
				outposts.append(poi)

	# Underflow: promote a random COMBAT in an outpost-free row.
	while outposts.size() < OUTPOST_MIN_PER_SECTOR:
		# Gather COMBAT candidates only from rows that have no outpost yet, so the
		# per-row cap (pass 1) is preserved.
		var candidates: Array = []
		for row in rows:
			var has_outpost: bool = false
			for poi in row.pois:
				if int(poi.node_type) == int(SectorNodeType.OUTPOST):
					has_outpost = true
					break
			if has_outpost:
				continue
			for poi in row.pois:
				if int(poi.node_type) == int(SectorNodeType.COMBAT):
					candidates.append(poi)
		if candidates.is_empty():
			break
		var victim = candidates[rng.randi() % candidates.size()]
		victim.node_type = int(SectorNodeType.OUTPOST)
		victim.hazard_subtype = ""
		outposts.append(victim)

	# Overflow safety rail (only reachable if OUTPOST_MAX_PER_SECTOR < row count).
	while outposts.size() > OUTPOST_MAX_PER_SECTOR:
		var idx: int = rng.randi() % outposts.size()
		var victim = outposts[idx]
		outposts.remove_at(idx)
		victim.node_type = int(SectorNodeType.COMBAT)


# Per-row POI generation. Picks 2-4 POIs at cell-snapped x-positions
# between PLANET_START_X (128) and the boss column (448). Types follow
# the dev v3 weights: combat-heavy, sprinkled outpost/hazard/signal.
func _gen_row_pois(rng: RandomNumberGenerator, sector_idx: int, row_idx: int, anchor: Vector2, _sector_mod_pool: Array = []) -> Array:
	const CELL_PX: float = 16.0
	const POI_X_MIN: float = 128.0
	const POI_X_MAX: float = 432.0  # one cell short of boss column (448)
	var count: int = rng.randi_range(3, 5)
	var positions: Array = []
	# Sample evenly with jitter so POIs don't pile up.
	var step: float = (POI_X_MAX - POI_X_MIN) / float(count)
	for i in range(count):
		var base_x: float = POI_X_MIN + step * (0.5 + float(i))
		var jitter: float = rng.randf_range(-step * 0.25, step * 0.25)
		var x: float = base_x + jitter
		x = float(int(x / CELL_PX)) * CELL_PX
		positions.append(x)
	var pois: Array = []
	for i in range(positions.size()):
		var node_type: int = _roll_poi_type(rng)
		# Dev: force every POI to a Signal Event for testing the signal screen
		# (set via the Test Combat "All-Signal Sector" launcher). Bosses are a
		# separate row, untouched. One-run-scoped — cleared in new_run().
		if has_meta("force_all_signal"):
			node_type = int(SectorNodeType.SIGNAL)
		var hazard_sub: String = ""
		if node_type == int(SectorNodeType.HAZARD):
			# asteroid_field RETIRED as a hazard subtype (2026-07-18, stronghold go-live): hazard nodes
			# are all minefields now; the asteroid content moved to the STRONGHOLD node type (promotion
			# pass in start_new_sector) + rock-peppered combat on asteroid POIs. The rng roll is KEPT
			# (result discarded) so the rng-call count — and therefore positions/bosses — match the
			# pre-retirement maps for a given seed.
			var _dead_roll: int = rng.randi() % 2
			hazard_sub = "minefield"
		# Per-POI modifier: chance to be null, else roll one from the FULL modifier range
		# (Roman 2026-06-09 — was drawing from a tiny per-sector pool, which made early sectors
		# show the same single modifier on every POI). Independent per-POI roll → a sector now
		# shows the full variety. The rng calls run UNCONDITIONALLY (even while the system is
		# disabled) so the RNG-call count — and therefore positions/bosses — never shifts with
		# the SECTOR_MODIFIERS_ENABLED flag.
		var poi_mods: Array = []
		var _mod_roll: float = rng.randf()
		var _mod_pick: int = rng.randi() % ALL_SECTOR_MODIFIERS.size()
		if SECTOR_MODIFIERS_ENABLED and _mod_roll >= POI_NULL_MODIFIER_CHANCE:
			poi_mods = [ALL_SECTOR_MODIFIERS[_mod_pick]]
		var poi_id: String = "s%d_r%d_p%d" % [sector_idx, row_idx, i]
		pois.append({
			"id": poi_id,
			"node_type": node_type,
			"hazard_subtype": hazard_sub,
			"pos": Vector2(positions[i], anchor.y),
			"completed": false,
			"modifiers": poi_mods,
			# M6b: faction is now a PROPERTY OF THE NODE (Roman 2026-06-11), assigned
			# deterministically per-POI so the sector map can color each combat node's
			# decoration by the faction the player will actually fight there. COMBAT
			# nodes only; -1 (none) for outpost/signal/hazard/boss. Seeded off run_seed
			# ^ hash(id) so it DOESN'T consume the shared `rng` (which would shift
			# positions/bosses — see the modifier-roll note above).
			"faction": _faction_for_poi(poi_id) if node_type == int(SectorNodeType.COMBAT) else -1,
		})
	return pois


const STRONGHOLD_MAX_PER_ROW: int = 2      # ≤2 stronghold assaults per system line (Roman 2026-07-18)
const STRONGHOLD_MAX_PER_SECTOR: int = 4   # ≤4 in the full sector
const STRONGHOLD_CHANCE: float = 0.5       # per eligible asteroid-POI combat node (before caps)


# Promote eligible COMBAT POIs to STRONGHOLD (Asteroid Stronghold assault) nodes. Eligible = the POI's
# deterministic deco kind is an asteroid (large_asteroid/cluster, NOT planet), so the map decoration +
# combat backdrop already show asteroid scenery there. Walks rows top-to-bottom, POIs left-to-right,
# rolling per-POI on a decorrelated rng; row/sector caps enforce Roman's ≤2-per-line / ≤4-per-sector.
# The node keeps its combat faction (a stronghold assault is faction combat with the ground overlay).
func _promote_stronghold_pois(rows: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value) ^ 0x53544841   # "STHA" — decorrelated from the sector-gen rng
	var sector_total: int = 0
	for row in rows:
		var row_total: int = 0
		for poi in row.get("pois", []):
			if sector_total >= STRONGHOLD_MAX_PER_SECTOR or row_total >= STRONGHOLD_MAX_PER_ROW:
				break
			if int(poi.get("node_type", -1)) != int(SectorNodeType.COMBAT):
				continue
			if _poi_obj_kind(String(poi.get("id", ""))) == 0:
				continue   # planet POI — strongholds sit on asteroid POIs (for now; more kinds later)
			if rng.randf() >= STRONGHOLD_CHANCE:
				continue
			poi["node_type"] = int(SectorNodeType.STRONGHOLD)
			row_total += 1
			sector_total += 1


# The POI's deterministic map-deco object kind: 0 = planet, 1 = large_asteroid, 2 = cluster.
# MUST mirror the deco seeding in sector_map_v3._build_pois_from_cache / StellarGameplay
# .compute_poi_stellar (abs(hash(id) ^ run_seed), first randi() % 3) so gen-time eligibility,
# the map render, and the combat backdrop all agree on what scenery the node sits on.
func _poi_obj_kind(poi_id: String) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = abs(hash(poi_id) ^ int(run_seed))
	return r.randi() % 3


# Deterministic per-node faction (0-3, matching Factions.Id). Uses its own RNG
# seeded from run_seed ^ hash(poi_id) so node faction is stable across map rebuilds
# and independent of visit order, without perturbing the sector-gen rng.
func _faction_for_poi(poi_id: String) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = int(run_seed) ^ abs(hash(poi_id))
	return r.randi() % 4


# Look up a cached POI's assigned faction by node id (-1 if not found / non-combat).
# main.gd reads this so the combat the player enters matches the map's decoration.
func get_node_faction(node_id: String) -> int:
	for row in sector_map_cache.get("rows", []):
		for poi in row.get("pois", []):
			if String(poi.get("id", "")) == node_id:
				return int(poi.get("faction", -1))
	return -1


# Boss roster + never-pair rules. A run is one sector of 3 rows; each row's boss
# is drawn from all 7 below (no per-sector pools, no Conductor finale-lock — both
# retired with the single-sector switch), avoiding these forbidden pairs
# ("never-pair-with" from the boss proposal):
#   Commander  never with Voidmaw  (both BH)
#   Lash       never with Howler   (both aggro)
#   Aegis      never with Spinwright (both long tanks)
#   Howler     never with Commander (both summon-stationary feel)
const BOSS_COMMANDER  := "res://scenes/enemies/bosses/boss.tscn"
const BOSS_LASH       := "res://scenes/enemies/bosses/boss_reaver.tscn"
const BOSS_HOWLER     := "res://scenes/enemies/bosses/boss_howler.tscn"
const BOSS_AEGIS      := "res://scenes/enemies/bosses/boss_sentinel.tscn"
const BOSS_VOIDMAW    := "res://scenes/enemies/bosses/boss_voidmaw.tscn"
const BOSS_SPINWRIGHT := "res://scenes/enemies/bosses/boss_spinwright.tscn"
const BOSS_CONDUCTOR  := "res://scenes/enemies/bosses/boss_conductor.tscn"

const _BOSS_CONFLICTS := {
	BOSS_COMMANDER:  [BOSS_VOIDMAW, BOSS_HOWLER],
	BOSS_VOIDMAW:    [BOSS_COMMANDER],
	BOSS_LASH:       [BOSS_HOWLER],
	BOSS_HOWLER:     [BOSS_LASH, BOSS_COMMANDER],
	BOSS_AEGIS:      [BOSS_SPINWRIGHT],
	BOSS_SPINWRIGHT: [BOSS_AEGIS],
}


# Returns a 3-element Array[String] of boss scene paths, one per row. The
# final boss (Conductor) is locked to sector-3 row-3. `prior_bosses` lists
# scene paths already used in previous sectors — excluded from the pool so
# no boss repeats across sectors in the same run.
func _pick_row_bosses(_sector_idx: int, rng: RandomNumberGenerator, prior_bosses: Array = []) -> Array:
	# Single-sector run (TOTAL_SECTORS = 1): all 7 bosses are eligible for any of
	# the 3 rows, drawn at random with conflict-pair + no-repeat-within-sector
	# rules. The Conductor is no longer locked to a finale slot (no multi-sector
	# final). prior_bosses still de-dupes across sectors should an endless/multi-
	# sector mode ever drive this again; if that empties the roster the full pool
	# is restored so the draw never starves.
	var full_pool: Array = [
		BOSS_COMMANDER, BOSS_LASH, BOSS_HOWLER, BOSS_VOIDMAW,
		BOSS_AEGIS, BOSS_SPINWRIGHT, BOSS_CONDUCTOR,
	]
	var pool: Array = full_pool.filter(func(b): return not prior_bosses.has(b))
	if pool.is_empty():
		pool = full_pool.duplicate()
	var picks: Array = []
	for _slot in range(3):
		var candidates: Array = []
		for b in pool:
			# Skip if conflicts with any already-picked.
			var ok: bool = true
			for chosen in picks:
				var clist: Array = _BOSS_CONFLICTS.get(chosen, [])
				if clist.has(b):
					ok = false
					break
				var clist2: Array = _BOSS_CONFLICTS.get(b, [])
				if clist2.has(chosen):
					ok = false
					break
			if ok:
				candidates.append(b)
		if candidates.is_empty():
			# Every remaining boss conflicts with a pick — fall back to what's left.
			candidates = pool.duplicate()
		var chosen: String = candidates[rng.randi() % candidates.size()]
		picks.append(chosen)
		# Remove so it can't be picked again for another row this sector
		# (Bug fix 2026-05-26: Howler repeating).
		pool.erase(chosen)
	return picks


func _roll_poi_type(rng: RandomNumberGenerator) -> int:
	# Outposts are NO LONGER POIs (reached via the sector-map "Visit Outpost" button,
	# Roman 2026-06-08) — dropped from the procedural pool. Re-weighted to
	# combat 5/9, hazard 2/9, signal 2/9.
	var r: int = rng.randi() % 9
	if r < 5: return int(SectorNodeType.COMBAT)
	if r < 7: return int(SectorNodeType.HAZARD)
	return int(SectorNodeType.SIGNAL)


# Look up a node (POI or boss) by id. Returns null if not found.
func find_sector_node(node_id: String):
	if sector_map_cache.is_empty() or not sector_map_cache.has("rows"):
		return null
	for row in sector_map_cache.rows:
		if row.boss.id == node_id:
			return row.boss
		for poi in row.pois:
			if poi.id == node_id:
				return poi
	return null


# Mark a node completed by id. Called by combat / outpost / signal scenes
# on their respective exit paths. Silent no-op if id is unknown so we
# don't blow up on Test Hazard launches with synthetic ids.
func mark_node_completed(node_id: String) -> void:
	var n = find_sector_node(node_id)
	if n == null:
		return
	var already: bool = bool(n.get("completed", false))
	n.completed = true
	if already:
		return  # don't double-tally a re-completion
	# Phase 2 visit tally — combat/hazard = a "location", signal = a "signal".
	# (Outposts aren't POIs in V3, so "stations" is tallied at outpost entry.)
	match int(n.get("node_type", -1)):
		SectorNodeType.COMBAT, SectorNodeType.HAZARD:
			stat_add("locations_visited", 1)
		SectorNodeType.SIGNAL:
			stat_add("signals_visited", 1)


# True when every POI on the given row is completed. Drives the boss-lock.
func is_row_pois_complete(row_idx: int) -> bool:
	if sector_map_cache.is_empty():
		return false
	var rows: Array = sector_map_cache.get("rows", [])
	if row_idx < 0 or row_idx >= rows.size():
		return false
	for poi in rows[row_idx].pois:
		if not poi.completed:
			return false
	return true


# True when all 3 row bosses are dead. Sector advances on next map entry.
func is_sector_complete() -> bool:
	if sector_map_cache.is_empty():
		return false
	for row in sector_map_cache.get("rows", []):
		if not row.boss.completed:
			return false
	return true

# Generalized equip path used by meta scenes (outpost + sector map manage-ship modal).
# Looks at part.slot_type and:
#   - displaces whatever was in that slot of loadout_snapshot into weapon_storage
#   - writes the new part into loadout_snapshot[slot]
#   - for ammo-bearing HARDPOINT_WING parts, seeds Run.secondary_ammo so a fresh
#     magazine survives until next combat (where the part's apply() reads it back)
#   - for DEVICE_BAY_1 parts, refills super charges (mirrors outpost convention).
# No live Player exists in meta scenes, so player-side apply runs at next combat.
const _SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const _PartFactory = preload("res://scripts/parts/part_factory.gd")
const _PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const _BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const _SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
const _FocusMode = preload("res://scripts/parts/focus_mode.gd")
const _BulletDefault = preload("res://scenes/projectiles/bullet_blaster.tscn")


# Seed loadout_snapshot + cannon_pool + the module bay with the chosen ship's starting
# kit (2026-07-11 — per-ship kits from ShipCatalog `loadout`; docs/
# ship_starting_loadouts_2026-07-11.md). A ship with no `loadout` entry (or a missing
# key) gets the classic defaults: Energy Blaster + Smart Bomb + Focus + Shield Core.
# Without this, meta scenes (sector map Manage Ship modal, outpost loadout line) see an
# empty dict for the swappable slots until the player performs their first outpost swap.
# Called from new_run() and apply_conditions() (so the start.no_* gates fire against the
# just-installed conditions) — must therefore be idempotent for a given ship_variant.
func _seed_default_loadout_snapshot() -> void:
	var kit: Dictionary = _ship_kit()
	# ---- Cannons: pool[0] = permanent infinite blaster, pool[1] = optional metered
	# primary (the two-slot model). A kit "blaster" replaces the Energy Blaster at [0];
	# a kit "primary" rides at [1] and starts ACTIVE (its dry-out swaps back to [0]).
	var blaster = _make_kit_part(kit.get("blaster")) if kit.has("blaster") else null
	if blaster == null:
		blaster = _make_default_blaster()
	cannon_pool = [blaster]
	active_cannon_idx = 0
	if kit.has("primary"):
		var prim = _make_kit_part(kit.get("primary"))
		if prim != null:
			# Seed the magazine exactly like _equip_primary does on a shop buy.
			if prim.has_method("ammo_at_mark") and "current_ammo" in prim and "ammo_max" in prim:
				var mag: int = int(prim.ammo_at_mark(int(prim.mark)))
				if mag >= 0:
					mag = cond_ammo_cap(mag)  # More Ammo capacity boost
					prim.current_ammo = mag
					prim.ammo_max = mag
			cannon_pool.append(prim)
			active_cannon_idx = 1
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()
	# ---- Wing secondary: pre-equipped stand-off munition (Weaver's Seeking Missile).
	if kit.has("secondary"):
		var sec = _make_kit_part(kit.get("secondary"))
		if sec != null:
			loadout_snapshot[_SlotTypes.SlotType.HARDPOINT_WING] = sec
			_seed_secondary_ammo(sec, true)
	# Sector Conditions — No Starting Super skips the universal smart-bomb (mirrors
	# PartFactory.default_starting_loadout so the meta-scene snapshot agrees with the ship).
	if not cond_flag("start.no_super"):
		var super_part = _PartFactory._load_or_default(
			"res://resources/weapons/smart_bomb.tres", _SmartBomb)
		loadout_snapshot[_SlotTypes.SlotType.DEVICE_BAY_1] = super_part
		# Smart Bomb hasn't run apply() on a player yet (no live player in meta
		# scenes), so seed super_charges from the part's per-mark formula directly
		# so the Manage Ship modal's "Super x/y" reads correctly on a fresh run.
		_seed_super_from_part(super_part)
	# Shift-Mode slot: the kit's signature mode, else Focus — unless No Starting Mode.
	if not cond_flag("start.no_mode"):
		var mode = _make_kit_part(kit.get("mode")) if kit.has("mode") else null
		loadout_snapshot[_SlotTypes.SlotType.SHIFT_MODE] = mode if mode != null else _FocusMode.new()
	# ---- Module bay: the kit list (shieldless kits simply list no core), else the
	# classic default Shield Core. Rebuilt wholesale — seed-time only, nothing acquired yet.
	if kit.has("modules"):
		modules = []
		for spec in kit.get("modules"):
			var m = _make_kit_part(spec)
			if m != null:
				modules.append(m)
	else:
		modules = [_ShieldCore.new()]
	_seed_meta_stats_from_modules()


# The chosen hull's starting-kit dict from ShipCatalog ({} = classic defaults).
func _ship_kit() -> Dictionary:
	var kit = ShipCatalog.get_ship(ship_variant).get("loadout", {})
	return kit if kit is Dictionary else {}


# Build one kit part from its ShipCatalog spec — "factory" or [factory, mk] — via
# PartCatalog.make_part (same construction as shop rolls: .tres stats, bullet
# fallbacks, identity stamping). Unknown factories error loudly and seed nothing.
func _make_kit_part(spec):
	var factory := ""
	var mk := 1
	if spec is String:
		factory = spec
	elif spec is Array and spec.size() >= 1:
		factory = String(spec[0])
		if spec.size() >= 2:
			mk = int(spec[1])
	if factory == "":
		return null
	var part = _PartCatalog.make_part(factory, mk)
	if part == null:
		push_error("ShipKit: unknown part factory '%s' (ship_variant %d)" % [factory, ship_variant])
	return part


# Reinforced Hull pips currently in the module bay — mini(mark,8) per reinforced_hull
# module, summed. SSOT for the hull-pip half of the max-hull formula; mirrors
# reinforced_hull.gd's _pips() EXACTLY so this and the player's module_hull_bonus
# (set by that part's apply) can never diverge.
func module_hull_pips() -> int:
	var pips := 0
	for m in modules:
		if m == null:
			continue
		if "module_id" in m and String(m.module_id) == "reinforced_hull":
			pips += mini(int(m.mark), 8)
	return pips


# THE single max-hull formula: base 2 + Reinforced Hull pips + Better Hull condition.
# Base is 2 — the documented player-side spec (player.gd apply_run_upgrades). The meta
# seed formerly used 3 (a stray "danger pip"), a latent split-owner bug that made a
# conditionless fresh run show 3 at the dock but 2 in combat; base 2 here is correct and
# intentionally changes the dock's fresh-run display from 3 to 2. Both the dock (via
# _seed_meta_stats_from_modules) and combat (player.apply_run_upgrades) route through
# this, so they can never disagree again.
func effective_max_hull() -> int:
	return 2 + module_hull_pips() + int(cond_sum("player.hull_bonus"))


# Mirror the seeded module bay into the Run meta stats (max_hull/max_shield + currents)
# so meta scenes show the kit's real capacities before the first combat writes back.
# Mirrors player.apply_run_upgrades' assembly: core-driven shield base (max-wins) + Mk
# capacity bonuses − Overcharge's −1, then the Weak/Better Shields scale; hull via the
# shared effective_max_hull() formula.
func _seed_meta_stats_from_modules() -> void:
	var shield_base := 0
	var shield_bonus := 0
	for m in modules:
		if m == null:
			continue
		if m.has_method("base_charges"):
			shield_base = maxi(shield_base, int(m.base_charges()))
		if m.has_method("_capacity_bonus"):
			shield_bonus += int(m._capacity_bonus())
		if "module_id" in m and String(m.module_id) == "overcharge_core":
			shield_bonus -= 1
	max_shield = maxi(0, shield_base + shield_bonus) if shield_base > 0 else 0
	# Sector Conditions — Weak/Better Shields scale the assembled charge pool, but only
	# when a shield actually exists (respect the shieldless gate). Mirrors player.gd
	# apply_run_upgrades so the dock's charge count matches combat's.
	if max_shield > 0:
		max_shield = maxi(1, roundi(max_shield * cond_scalar("player.shield_charges_mult")))
	current_shield = max_shield
	max_hull = effective_max_hull()
	current_hull = max_hull


# Re-seed the starting kit for the CURRENT ship_variant. Front-ends that pick a hull
# (patrol_start) call this right after writing ship_variant — new_run() has already
# seeded, but with the default variant 0 (the write comes after, by design; see the
# post-new_run pattern note at ship_variant's reset).
func reseed_loadout_for_ship() -> void:
	loadout_snapshot = {}
	_seed_default_loadout_snapshot()


# Derive the max super charges a DEVICE_BAY_1 part would grant at its current
# Mk, WITHOUT needing a live player. Mirrors what the part's apply(ship) does
# at combat start. Used by equip_part / _seed_default_loadout_snapshot so the
# Run.max_super_charges is always consistent for meta-scene reads (Hangar UI,
# Manage Ship modal, outpost super refill action).
#
# Per the no-silent-fallbacks rule: prefer the part's own _charges_at_mark()
# method; fall back to the documented base_charges + (mark-1)*charges_per_mark
# convention every super part in scripts/parts/ exposes; otherwise warn loudly
# and return 1 so the super is at least usable.
func _super_charges_from_part(part) -> int:
	if part == null:
		return 0
	if part.has_method("_charges_at_mark"):
		return int(part._charges_at_mark(int(part.mark)))
	if "base_charges" in part and "charges_per_mark" in part:
		return int(part.base_charges) + (int(part.mark) - 1) * int(part.charges_per_mark)
	push_warning("Run._super_charges_from_part: part %s has no _charges_at_mark / base_charges — defaulting to 1" % part)
	return 1


# Seed Run.secondary_ammo / _max from a HARDPOINT_WING part's per-Mk ammo. Honors both the
# new `_base_ammo()` method and legacy @export `base_ammo`. reset_if_none: on a fresh equip an
# unmetered/zero-ammo secondary clears the pool to -1; on an in-place Mk upgrade it leaves the
# existing pool untouched (an upgrade must never wipe ammo). (Health audit 2026-06-15.)
# Sector Conditions — More Ammo scales a metered capacity. Applied at the CAP-ESTABLISHING
# points only (each cap scaled exactly once; unmetered <= 0 passes through untouched). This is
# the run-side cap seam — the ship seeds its live magazine from these (current_ammo / Run
# secondary_ammo), so scaling here is the single place the boost enters. Rounded, floored at 1.
func cond_ammo_cap(base: int) -> int:
	if base <= 0:
		return base
	return maxi(1, roundi(base * cond_scalar("player.ammo_max_mult")))


func _seed_secondary_ammo(part, reset_if_none: bool) -> void:
	var sec_ammo: int = -1
	if part.has_method("_base_ammo"):
		sec_ammo = int(part._base_ammo())
	elif "base_ammo" in part:
		sec_ammo = int(part.base_ammo)
	if sec_ammo > 0:
		sec_ammo = cond_ammo_cap(sec_ammo)  # More Ammo capacity boost
		secondary_ammo = sec_ammo
		secondary_ammo_max = sec_ammo
	elif reset_if_none:
		secondary_ammo = -1
		secondary_ammo_max = -1


# Seed Run.super_charges / max from a DEVICE_BAY_1 part's per-Mk charge formula — the part's
# apply(ship) only runs at combat start, so meta-scene seeding/re-equip/upgrade need this.
# (Health audit 2026-06-15.)
func _seed_super_from_part(part) -> void:
	max_super_charges = _super_charges_from_part(part)
	super_charges = int(max_super_charges)


func equip_part(part) -> void:
	if part == null:
		return
	var slot: int = int(part.slot_type)
	# CANNON: two-slot model (Roman 2026-06-11). An INFINITE cannon replaces the
	# BLASTER (slot 0, the fallback); a METERED one replaces the PRIMARY (slot 1).
	# The displaced weapon goes to the sellable hold (weapon_storage).
	if slot == _SlotTypes.SlotType.CANNON:
		_equip_cannon(part)
		return
	var prev = loadout_snapshot.get(slot, null)
	if prev != null:
		weapon_storage.append(prev)
	loadout_snapshot[slot] = part
	if slot == _SlotTypes.SlotType.HARDPOINT_WING:
		_seed_secondary_ammo(part, true)
	if slot == _SlotTypes.SlotType.DEVICE_BAY_1:
		# Reseed max_super_charges from the part's per-Mk formula here. The
		# part's apply(ship) only runs at combat start, so without this any
		# meta-scene re-equip (Hangar clear + re-equip, outpost swap) would
		# leave max_super_charges at whatever the previous super left behind
		# (or 0 after unequip_slot). See _seed_default_loadout_snapshot for
		# the same pattern used on first run.
		_seed_super_from_part(part)


# ---- Cannon pool helpers (Weapons Phase 1) -----------------------------

# Active cannon Part — what player.fire_primary should be using. Returns
# null if pool is empty (shouldn't happen — blaster is permanent).
func get_active_cannon():
	if cannon_pool.is_empty():
		return null
	var idx: int = clampi(active_cannon_idx, 0, cannon_pool.size() - 1)
	return cannon_pool[idx]


# ---- Two-slot cannon model (Blaster + Primary, Roman 2026-06-11) -----------
# cannon_pool[0] = BLASTER (infinite, the fallback). cannon_pool[1] = PRIMARY
# (metered; lasers regen) or absent. active_cannon_idx (0/1) = which one FIRES;
# Q toggles it (cycle_primary). A dry NON-regen primary auto-reverts to the
# blaster (swap_to_blaster) WITHOUT losing the primary (it stays in slot 1 to be
# refilled). Equipping routes by type; the displaced weapon → sellable hold.

# Route a CANNON-slot part to the blaster or primary slot by its ammo type.
func _equip_cannon(part) -> void:
	if part == null:
		return
	_ensure_blaster_slot()
	if _is_infinite_cannon(part):
		_equip_blaster(part)
	else:
		_equip_primary(part)


# Guarantee cannon_pool[0] is an infinite blaster (defensive; first run seeds it).
func _ensure_blaster_slot() -> void:
	if cannon_pool.is_empty() or not _is_infinite_cannon(cannon_pool[0]):
		cannon_pool.insert(0, _make_default_blaster())
	active_cannon_idx = clampi(active_cannon_idx, 0, cannon_pool.size() - 1)


# The equipped primary (cannon_pool[1]) or null.
func get_primary_cannon():
	return cannon_pool[1] if cannon_pool.size() > 1 else null


# Internal Micro Fabricator (module): top up the persistent metered-ammo pools by
# `pct` of each weapon's max, capped at max. Primary magazine lives on the cannon
# Part (current_ammo/ammo_max); secondary on secondary_ammo/secondary_ammo_max.
# Infinite blasters (ammo_max <= 0) and unmetered secondaries (-1) are skipped.
# ceil() guarantees at least +1 per clear for any metered weapon.
func restock_ammo_fraction(pct: float) -> void:
	if pct <= 0.0:
		return
	# Primary — the metered cannon (cannon_pool[1]).
	var prim = get_primary_cannon()
	if prim != null and "current_ammo" in prim and "ammo_max" in prim:
		var pmax: int = int(prim.ammo_max)
		if pmax > 0:
			var cur: int = int(prim.current_ammo)
			if cur < 0:
				cur = pmax
			var topped: int = mini(pmax, cur + int(ceil(float(pmax) * pct)))
			prim.current_ammo = topped
			# Mirror Run.ammo when the primary is the active cannon (live magazine).
			if active_cannon_idx == 1:
				ammo = topped
	# Secondary — Run-persisted pool.
	if secondary_ammo_max > 0 and secondary_ammo >= 0:
		secondary_ammo = mini(secondary_ammo_max, secondary_ammo + int(ceil(float(secondary_ammo_max) * pct)))


# Laser-family primaries (ammo_recharge_rate > 0 — Auto/Pulse/Rotary/Quad lasers)
# already regenerate ammo IN combat; on top of that they arrive FULL at the outpost.
# Every level clear tops the laser magazine back to max. Non-regen metered weapons
# (Autocannon/Minigun/Shredder, recharge 0) get nothing here — they rely on the
# Internal Micro Fabricator's partial restock instead. Secondaries are likewise the
# Fabricator's job, not this one. (Roman 2026-06-23.)
func restock_regen_laser_primary() -> void:
	var prim = get_primary_cannon()
	if prim == null:
		return
	if not ("ammo_recharge_rate" in prim) or float(prim.ammo_recharge_rate) <= 0.0:
		return  # not a regen laser — leave it to the Micro Fabricator
	if not ("current_ammo" in prim and "ammo_max" in prim):
		return
	var pmax: int = int(prim.ammo_max)
	if pmax <= 0:
		return
	prim.current_ammo = pmax
	# Mirror Run.ammo when the laser is the active (loaded) cannon.
	if active_cannon_idx == 1:
		ammo = pmax


# Replace the BLASTER (slot 0). Old blaster → hold; same-name = mark-bump.
func _equip_blaster(part) -> void:
	var pname: String = String(part.display_name)
	var cur = cannon_pool[0] if cannon_pool.size() > 0 else null
	if cur != null and String(cur.display_name) == pname:
		mark_bump_owned_cannon(part)
	else:
		_remove_cannon_from_hold_by_name(pname)
		if cur != null:
			weapon_storage.append(cur)
		if cannon_pool.is_empty():
			cannon_pool.append(part)
		else:
			cannon_pool[0] = part
	active_cannon_idx = 0   # show the freshly-equipped blaster
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()


# Replace the PRIMARY (slot 1). Old primary → hold; same-name = mark-bump. Seeds a
# fresh metered magazine; a hold cannon keeps its stored ammo (no free refill).
func _equip_primary(part) -> void:
	var pname: String = String(part.display_name)
	var cur = get_primary_cannon()
	if cur != null and String(cur.display_name) == pname:
		mark_bump_owned_cannon(part)
		active_cannon_idx = 1
		loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()
		return
	_remove_cannon_from_hold_by_name(pname)
	if part.has_method("ammo_at_mark") and "current_ammo" in part and "ammo_max" in part:
		var mag: int = int(part.ammo_at_mark(int(part.mark)))
		if mag >= 0 and int(part.current_ammo) < 0:
			mag = cond_ammo_cap(mag)  # More Ammo capacity boost
			part.current_ammo = mag
			part.ammo_max = mag
	if cur != null:
		weapon_storage.append(cur)
	_ensure_blaster_slot()
	if cannon_pool.size() > 1:
		cannon_pool[1] = part
	else:
		cannon_pool.append(part)
	active_cannon_idx = 1   # auto-switch to the new primary
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()


# Q toggle: switch the firing cannon between blaster (0) and primary (1). No-op
# (forces blaster) if no primary is equipped.
func cycle_primary() -> void:
	if cannon_pool.size() <= 1:
		active_cannon_idx = 0
		return
	active_cannon_idx = 1 if active_cannon_idx == 0 else 0
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()


# Set the firing cannon to a specific slot (Manage Ship). Clamped; the primary
# stays equipped either way.
func set_active_cannon(idx: int) -> void:
	if cannon_pool.is_empty():
		return
	active_cannon_idx = clampi(idx, 0, cannon_pool.size() - 1)
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()


# Auto-revert: a dry NON-regen primary falls back to the blaster (slot 0). The
# primary STAYS equipped in slot 1 (refill at an outpost, then Q back).
func swap_to_blaster() -> void:
	active_cannon_idx = 0
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = get_active_cannon()


# True when a cannon Part never meters ammo (ammo_at_mark == -1).
func _is_infinite_cannon(part) -> bool:
	if part == null or not part.has_method("ammo_at_mark"):
		return false
	var mk: int = int(part.mark) if "mark" in part else 1
	return int(part.ammo_at_mark(mk)) < 0


# Is the currently-FIRING cannon an infinite blaster (no refills / no dry-out)?
func is_active_cannon_infinite() -> bool:
	return _is_infinite_cannon(get_active_cannon())


# Remove a CANNON from the hold by name (used when re-equipping an owned one).
func _remove_cannon_from_hold_by_name(pname: String) -> void:
	for i in range(weapon_storage.size()):
		var w = weapon_storage[i]
		if w != null and "slot_type" in w and int(w.slot_type) == _SlotTypes.SlotType.CANNON \
				and String(w.display_name) == pname:
			weapon_storage.remove_at(i)
			return


func _make_default_blaster():
	var cannon = _PartFactory._load_or_default(
		"res://resources/weapons/energy_blaster.tres", _BasicBlasterCannon)
	if "bullet_scene" in cannon and cannon.bullet_scene == null:
		cannon.bullet_scene = _BulletDefault
	return cannon


# Look up an owned cannon by display_name. Returns the cannon_pool index
# or -1 if not owned. Used by the outpost dedupe-up roll.
func find_owned_cannon_by_name(name: String) -> int:
	for i in range(cannon_pool.size()):
		var c = cannon_pool[i]
		if c != null and String(c.display_name) == name:
			return i
	return -1


# Mark of an owned cannon (active OR in the hold), or -1 if not owned. The
# outpost dedupe-up uses this so re-offering a stowed cannon also bumps its
# mark instead of duplicating it.
func owned_cannon_mark(name: String) -> int:
	var a = get_active_cannon()
	if a != null and String(a.display_name) == name:
		return int(a.mark) if "mark" in a else 1
	for w in weapon_storage:
		if w != null and "slot_type" in w and int(w.slot_type) == _SlotTypes.SlotType.CANNON \
				and String(w.display_name) == name:
			return int(w.mark) if "mark" in w else 1
	return -1


# Mark-bump an owned cannon. `bump_part` is the freshly-rolled +1 Mk Part
# the player just bought; we read its mark and re-apply it to the OWNED
# entry so a single dedupe-up purchase doesn't create a duplicate. Refills
# ammo from the new mark's curve.
func mark_bump_owned_cannon(bump_part) -> void:
	if bump_part == null:
		return
	var idx: int = find_owned_cannon_by_name(String(bump_part.display_name))
	if idx < 0:
		push_warning("Run.mark_bump_owned_cannon: %s not owned" % bump_part.display_name)
		return
	var owned = cannon_pool[idx]
	if "mark" in owned and "mark" in bump_part:
		owned.mark = int(bump_part.mark)
	# Refill ammo from the new mark's per-mark formula.
	if owned.has_method("ammo_at_mark") and "current_ammo" in owned and "ammo_max" in owned:
		var seed: int = cond_ammo_cap(int(owned.ammo_at_mark(int(owned.mark))))  # More Ammo capacity boost
		owned.current_ammo = seed
		owned.ammo_max = seed
	# Keep loadout_snapshot mirror in sync if the bumped cannon is active.
	if idx == active_cannon_idx:
		loadout_snapshot[_SlotTypes.SlotType.CANNON] = owned


# ---- In-place Mk upgrade (Materials economy, Roman 2026-06-14) --------------
# The outpost spends Materials + bounty to raise an OWNED part's Mk by one. Part objects are
# mutated in place (the same Resource instances held in cannon_pool / loadout_snapshot /
# modules), so the higher Mk takes effect at the next combat start when the part's apply()
# re-reads `mark`. CANNON / HARDPOINT_WING / DEVICE_BAY_1 also carry derived Run-side state
# (magazines, super charges) that apply() doesn't reseed in meta scenes, so we reseed here —
# mirroring equip_part.
func can_upgrade_part(part) -> bool:
	if part == null or not ("mark" in part):
		return false
	var maxmk: int = int(part.max_mark) if "max_mark" in part else 9
	return int(part.mark) < maxmk


func upgrade_part(part) -> bool:
	if not can_upgrade_part(part):
		return false
	part.mark = int(part.mark) + 1
	_reseed_part_mark_state(part)
	return true


# Reseed Run-side derived state after a part's mark changes in place. Mirrors the per-slot
# seeding equip_part does on a fresh equip. SHIFT_MODE / MODULE need nothing here — their
# apply() reads `mark` live at combat start.
func _reseed_part_mark_state(part) -> void:
	if part == null or not ("slot_type" in part):
		return
	match int(part.slot_type):
		_SlotTypes.SlotType.CANNON:
			if part.has_method("ammo_at_mark") and "current_ammo" in part and "ammo_max" in part:
				var mag: int = cond_ammo_cap(int(part.ammo_at_mark(int(part.mark))))  # More Ammo capacity boost
				part.current_ammo = mag
				part.ammo_max = mag
				if get_active_cannon() == part:
					ammo = mag   # mirror the live magazine when upgrading the active cannon
		_SlotTypes.SlotType.HARDPOINT_WING:
			_seed_secondary_ammo(part, false)
		_SlotTypes.SlotType.DEVICE_BAY_1:
			_seed_super_from_part(part)


# Inverse of equip_part: clears a slot in loadout_snapshot and zeroes any
# per-slot side state (secondary ammo, super charges). Unlike equip_part this
# is an explicit discard — the removed part is NOT pushed into weapon_storage
# (the hangar treats it as a remove, not a swap). Silent no-op if slot is
# already empty.
func unequip_slot(slot: int) -> void:
	if not loadout_snapshot.has(slot):
		return
	loadout_snapshot.erase(slot)
	if slot == _SlotTypes.SlotType.HARDPOINT_WING:
		secondary_ammo = -1
		secondary_ammo_max = -1
	if slot == _SlotTypes.SlotType.DEVICE_BAY_1:
		super_charges = 0
		max_super_charges = 0


# ---- Run save / resume ------------------------------------------------
# Single-slot save written on sector map entry; consumed by Resume Patrol.
# Format: RunSave Resource serialized via ResourceSaver so embedded Part
# resources in loadout_snapshot / inventory / weapon_storage round-trip
# as inline sub-resources without us hand-rolling JSON for every Part type.

const _RunSave = preload("res://scripts/game/run_save.gd")
const SAVE_PATH := "user://run_save.tres"

# Fields mirrored to/from RunSave. Kept as a const so save_to_disk and
# load_from_disk can't drift out of sync — adding a field is a one-line
# change here + an @export in run_save.gd.
const _SAVE_FIELDS := [
	"bounty", "materials", "current_hull", "max_hull", "current_shield", "max_shield",
	"super_charges", "max_super_charges",
	"loadout_snapshot", "inventory", "weapon_storage",
	"current_node_id", "current_node_type", "sector_modifiers", "active_conditions",
	"current_hazard_subtype", "asteroid_bonus_bounty", "mine_bonus_bounty", "combat_intro",
	"current_stellar",
	"ammo", "secondary_ammo", "secondary_ammo_max",
	"visited_nodes", "sectors_cleared", "bosses_defeated", "combats_in_sector", "used_boss_scenes",
	"enemies_killed", "max_bounty_earned", "run_distance", "run_seed", "seed_was_custom",
	"ship_variant", "livery_color", "livery_chosen",
	"hull_mk", "armor_mk", "thrusters_mk", "self_repair_mk",
	"shield_cap_mk", "shield_recharge_mk", "hull_plating_mk",
	"sector_map_cache",
	"cannon_pool", "active_cannon_idx",
	"repair_charges", "ammo_restock_charges", "outpost_needs_refresh", "outpost_weapon_offers",
	"run_time_seconds", "run_stats",
	"modules", "bay_initialized",
]


# Startup guard against save-surface drift: the save/load loops only walk _SAVE_FIELDS, and
# RunSave only persists its @export vars — so the two lists must stay in lockstep. An @export
# missing from _SAVE_FIELDS silently never persists; a _SAVE_FIELDS entry with no @export
# round-trips null. Either is a quiet data-loss bug, so we warn loudly at boot instead.
# (Health audit 2026-06-15.)
func _assert_save_surface_synced() -> void:
	var rs = _RunSave.new()
	var rs_props := {}
	for prop in rs.get_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			rs_props[String(prop.name)] = true
	var saved := {}
	for f in _SAVE_FIELDS:
		saved[f] = true
		if not rs_props.has(f):
			push_warning("Run._SAVE_FIELDS has '%s' but RunSave has no matching @export — it round-trips null." % f)
	for pname in rs_props:
		if not saved.has(pname):
			push_warning("Run: RunSave.%s is @export'd but missing from _SAVE_FIELDS — it won't persist." % pname)


func has_save_on_disk() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_to_disk() -> void:
	var s = _RunSave.new()
	for f in _SAVE_FIELDS:
		s.set(f, get(f))
	var err: int = ResourceSaver.save(s, SAVE_PATH)
	if err != OK:
		push_warning("Run.save_to_disk: ResourceSaver.save failed (%d)" % err)


# Load saved run into this autoload. Returns true on success. On failure
# the autoload is left untouched and the save is wiped (corrupt slot).
func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var s = load(SAVE_PATH)
	if s == null or not (s is _RunSave):
		push_warning("Run.load_from_disk: save corrupt — wiping")
		clear_save()
		return false
	for f in _SAVE_FIELDS:
		set(f, s.get(f))
	# Save migration: pre-Phase-1 saves have no cannon_pool. Seed it from
	# loadout_snapshot[CANNON] so the player keeps their blaster on resume.
	if cannon_pool == null or cannon_pool.is_empty():
		var legacy_cannon = loadout_snapshot.get(_SlotTypes.SlotType.CANNON, null)
		if legacy_cannon != null:
			cannon_pool = [legacy_cannon]
		active_cannon_idx = 0
	# Save migration: pre-bay saves have no module bay (bay_initialized false → modules
	# loads as []). Seed the default Shield Core so a resumed old run keeps its shield
	# (an empty bay only means glass-cannon once bay_initialized is true).
	if not bay_initialized:
		modules = [_ShieldCore.new()]
		bay_initialized = true
	return true


func clear_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d := DirAccess.open("user://")
	if d != null:
		d.remove("run_save.tres")


# Snapshot player into RunState so we can restore after meta scenes.
func snapshot_player(player) -> void:
	current_hull = player.hull
	max_hull = player.max_hull
	current_shield = player.shield
	max_shield = player.max_shield
	if "super_charges" in player:
		super_charges = player.super_charges
	if "max_super_charges" in player:
		max_super_charges = player.max_super_charges
	if player.has_method("get_loadout"):
		loadout_snapshot = player.get_loadout()

# Apply snapshot back to a fresh player instance after re-entering combat.
func apply_to_player(player) -> void:
	if max_hull > 0:
		player.max_hull = max_hull
		player.hull = current_hull
	if max_shield > 0:
		player.max_shield = max_shield
		player.shield = current_shield
	if player.has_method("apply_loadout") and not loadout_snapshot.is_empty():
		player.apply_loadout(loadout_snapshot)
	# Restore super charges AFTER apply_loadout — loadout's apply()
	# would otherwise reset them to max via the Smart Bomb part's apply.
	if "super_charges" in player and max_super_charges > 0:
		player.max_super_charges = max_super_charges
		player.super_charges = super_charges
		if player.has_signal("super_charges_changed"):
			player.super_charges_changed.emit(super_charges, max_super_charges)
