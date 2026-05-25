extends Node

# Persistent run state. Autoloaded as "Run" so any scene can read/write.
# Survives scene changes; reset by new_run().

signal bounty_changed(value)
signal hull_changed(cur, max)
signal shield_changed(cur, max)

# Currency
var bounty: int = 0:
	set(v):
		bounty = max(0, v)
		bounty_changed.emit(bounty)

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

# Uninstalled parts the player is carrying (cargo hold). Used by Junk Trader
# and any future inventory UI. Each entry is a Part resource. The Junk Trader
# refuses to operate when this is empty.
var inventory: Array = []

# Sector progress
var current_node_id: String = ""
var current_node_type: int = -1  # SectorNode.NodeType; -1 if none
# Active sector modifiers for the current combat. Set by the sector map when
# the player enters a node; cleared on new_run(). Values: "shielded",
# "armored", "heavily_armored", "aggressive", "wanted", "fleeing", "dangerous".
var sector_modifiers: Array = []
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
# nebula_tint (Color). Empty until the first node click.
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
# Combat nodes (non-boss, non-hazard) completed since the start of the
# current sector. Drives wave_generator scaling. Resets to 0 when a new
# sector begins (endless mode).
var combats_in_sector: int = 0

# Stats
var enemies_killed: int = 0
var max_bounty_earned: int = 0
var run_distance: float = 0.0

# Random seed for reproducible runs (sector map + shop rolls).
var run_seed: int = 0

# ---- Persistent upgrades (outpost purchases) --------------------------
# Mk 0..9 per category. Applied to the player at combat start via
# player.apply_run_upgrades(). Increasing the Mk is the only path the
# player has to grow these stats — basic parts no longer add hull/shield.
var hull_mk: int = 0
var armor_mk: int = 0
var thrusters_mk: int = 0
var self_repair_mk: int = 0
var shield_cap_mk: int = 0
var shield_recharge_mk: int = 0

# Stored cannons swapped out at outposts (the new one takes the CANNON
# slot, the old one moves here). Each entry is a Part resource.
var weapon_storage: Array = []

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

func new_run() -> void:
	bounty = 0
	enemies_killed = 0
	max_bounty_earned = 0
	run_distance = 0.0
	sectors_cleared = 0
	combats_in_sector = 0
	visited_nodes = []
	current_node_id = ""
	sector_modifiers = []
	loadout_snapshot = {}
	inventory = []
	current_hull = 0
	max_hull = 0
	current_shield = 0
	max_shield = 0
	hull_mk = 0
	armor_mk = 0
	thrusters_mk = 0
	self_repair_mk = 0
	shield_cap_mk = 0
	shield_recharge_mk = 0
	weapon_storage = []
	sector_map_cache = {}
	# Reset ammo state — Part.apply() reseeds on equip.
	ammo = -1
	secondary_ammo = -1
	secondary_ammo_max = -1
	run_seed = randi()
	# Reset super-weapon state — player._ready will repopulate via the
	# equipped Smart Bomb's apply(). Seeded below so meta-scene reads
	# (Manage Ship modal, outpost status bar) match what combat will apply.
	super_charges = 0
	max_super_charges = 3
	# Seed default Energy Blaster + Smart Bomb so meta scenes see the same
	# loadout the combat scene will apply via PartFactory.default_starting_loadout.
	_seed_default_loadout_snapshot()

func record_kill(value: int) -> void:
	enemies_killed += 1
	bounty += value
	if bounty > max_bounty_earned:
		max_bounty_earned = bounty

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

const SectorNodeType = preload("res://scripts/sector_node.gd").NodeType
const SectorNameGenerator = preload("res://scripts/sector_name_generator.gd")

# Total sectors required to beat the game. Drives the "Sector Patrol X/Y"
# header in sector_map_v3. Designer-tunable — bump when adding mid/late
# sectors. Read by sector_map_v3 directly.
const TOTAL_SECTORS: int = 3

# (Re)generate the sector map cache for the given sector index + seed.
# Always overwrites; call when entering a fresh sector.
func start_new_sector(sector_idx: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rows: Array = []
	# Three rows, anchored at the same Y-coords the V3 map renders at.
	var anchors := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]
	var boss_positions := [Vector2(448, 64), Vector2(448, 128), Vector2(448, 192)]
	# Per-sector boss pool + final-slot lock. Sector 3 row-3 is always the
	# Conductor; the other two row slots pull from the sector pool minus the
	# Conductor, with conflict-pair rules applied (see _pick_row_bosses).
	var boss_scenes: Array = _pick_row_bosses(sector_idx, rng)
	for r in range(3):
		var pois: Array = _gen_row_pois(rng, sector_idx, r, anchors[r])
		var boss := {
			"id": "s%d_r%d_boss" % [sector_idx, r],
			"node_type": int(SectorNodeType.BOSS),
			"pos": boss_positions[r],
			"boss_scene": boss_scenes[r],
			"completed": false,
		}
		rows.append({
			"anchor": anchors[r],
			"boss": boss,
			"pois": pois,
		})
	sector_map_cache = {
		"sector_idx": sector_idx,
		"seed": seed_value,
		"sector_name": SectorNameGenerator.generate(seed_value),
		"rows": rows,
	}


# Per-row POI generation. Picks 2-4 POIs at cell-snapped x-positions
# between PLANET_START_X (128) and the boss column (448). Types follow
# the dev v3 weights: combat-heavy, sprinkled outpost/hazard/signal.
func _gen_row_pois(rng: RandomNumberGenerator, sector_idx: int, row_idx: int, anchor: Vector2) -> Array:
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
		var hazard_sub: String = ""
		if node_type == int(SectorNodeType.HAZARD):
			hazard_sub = "minefield" if rng.randi() % 2 == 0 else "asteroid_field"
		pois.append({
			"id": "s%d_r%d_p%d" % [sector_idx, row_idx, i],
			"node_type": node_type,
			"hazard_subtype": hazard_sub,
			"pos": Vector2(positions[i], anchor.y),
			"completed": false,
		})
	return pois


# Per-sector boss roster + never-pair rules. Sector 3 row-3 is always the
# Conductor (final). Other rows pull from sector pools and avoid forbidden
# pairs ("never-pair-with" from the boss proposal):
#   Commander  never with Voidmaw  (both BH)
#   Lash       never with Howler   (both aggro)
#   Aegis      never with Spinwright (both long tanks)
#   Howler     never with Commander (both summon-stationary feel)
const BOSS_COMMANDER  := "res://scenes/enemies/boss.tscn"
const BOSS_LASH       := "res://scenes/enemies/boss_reaver.tscn"
const BOSS_HOWLER     := "res://scenes/enemies/boss_howler.tscn"
const BOSS_AEGIS      := "res://scenes/enemies/boss_sentinel.tscn"
const BOSS_VOIDMAW    := "res://scenes/enemies/boss_voidmaw.tscn"
const BOSS_SPINWRIGHT := "res://scenes/enemies/boss_spinwright.tscn"
const BOSS_CONDUCTOR  := "res://scenes/enemies/boss_conductor.tscn"

const _BOSS_CONFLICTS := {
	BOSS_COMMANDER:  [BOSS_VOIDMAW, BOSS_HOWLER],
	BOSS_VOIDMAW:    [BOSS_COMMANDER],
	BOSS_LASH:       [BOSS_HOWLER],
	BOSS_HOWLER:     [BOSS_LASH, BOSS_COMMANDER],
	BOSS_AEGIS:      [BOSS_SPINWRIGHT],
	BOSS_SPINWRIGHT: [BOSS_AEGIS],
}


# Returns a 3-element Array[String] of boss scene paths, one per row. The
# final boss (Conductor) is locked to sector-3 row-3.
func _pick_row_bosses(sector_idx: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	if sector_idx <= 1:
		pool = [BOSS_COMMANDER, BOSS_LASH, BOSS_HOWLER]
	elif sector_idx == 2:
		pool = [BOSS_COMMANDER, BOSS_LASH, BOSS_VOIDMAW, BOSS_AEGIS, BOSS_SPINWRIGHT]
	else:
		pool = [BOSS_AEGIS, BOSS_VOIDMAW, BOSS_SPINWRIGHT]
	var picks: Array = []
	# Sector 3 row-3 final lock.
	var final_locked: bool = sector_idx >= 3
	var slots: int = 3
	for slot in range(slots):
		if final_locked and slot == slots - 1:
			picks.append(BOSS_CONDUCTOR)
			continue
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
			# Pool exhausted by conflicts — fall back to whatever's left in
			# the pool so we never push a Conductor or empty path here.
			candidates = pool.duplicate()
		picks.append(candidates[rng.randi() % candidates.size()])
	return picks


func _roll_poi_type(rng: RandomNumberGenerator) -> int:
	# Same weights as the dev v3 _pick_node_type, mapped to enum ints.
	# combat 4/9, outpost 2/9, hazard 2/9, signal 1/9
	var r: int = rng.randi() % 9
	if r < 4: return int(SectorNodeType.COMBAT)
	if r < 6: return int(SectorNodeType.OUTPOST)
	if r < 8: return int(SectorNodeType.HAZARD)
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
	if n != null:
		n.completed = true


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
const _BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const _SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
const _BulletDefault = preload("res://scenes/projectiles/bullet.tscn")


# Seed loadout_snapshot with the same Mk.1 defaults PartFactory.default_starting_loadout
# would equip on the player. Without this, meta scenes (sector map Manage Ship modal,
# outpost loadout line) see an empty dict for the swappable slots until the player
# performs their first outpost swap — leading to "PRIMARY: — (empty)" on a fresh run
# even though the player is flying with an Energy Blaster + Smart Bomb. Mirrors the
# PartFactory load path so a designer-edited .tres applies here too. Called from
# new_run() so the snapshot is always populated before any meta scene reads it.
func _seed_default_loadout_snapshot() -> void:
	var cannon = _PartFactory._load_or_default(
		"res://resources/weapons/energy_blaster.tres", _BasicBlasterCannon)
	if "bullet_scene" in cannon and cannon.bullet_scene == null:
		cannon.bullet_scene = _BulletDefault
	loadout_snapshot[_SlotTypes.SlotType.CANNON] = cannon
	var super_part = _PartFactory._load_or_default(
		"res://resources/weapons/smart_bomb.tres", _SmartBomb)
	loadout_snapshot[_SlotTypes.SlotType.DEVICE_BAY_1] = super_part
	# Smart Bomb hasn't run apply() on a player yet (no live player in meta
	# scenes), so seed super_charges from the part's per-mark formula directly
	# so the Manage Ship modal's "Super x/y" reads correctly on a fresh run.
	if super_part.has_method("_charges_at_mark"):
		max_super_charges = int(super_part._charges_at_mark(int(super_part.mark)))
		super_charges = max_super_charges


func equip_part(part) -> void:
	if part == null:
		return
	var slot: int = int(part.slot_type)
	var prev = loadout_snapshot.get(slot, null)
	if prev != null:
		weapon_storage.append(prev)
	loadout_snapshot[slot] = part
	if slot == _SlotTypes.SlotType.HARDPOINT_WING:
		if "base_ammo" in part and int(part.base_ammo) > 0:
			secondary_ammo = int(part.base_ammo)
			secondary_ammo_max = int(part.base_ammo)
		else:
			secondary_ammo = -1
			secondary_ammo_max = -1
	if slot == _SlotTypes.SlotType.DEVICE_BAY_1:
		super_charges = int(max_super_charges)


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
