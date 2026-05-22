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

# Generated sector map snapshot, keyed by str(run_seed). Lets the sector
# map scene restore the exact same graph after a combat/outpost round-trip
# instead of re-rolling procgen (which isn't fully deterministic across
# instantiations even with a locked seed).
var sector_map_cache: Dictionary = {}

func _ready() -> void:
	# Cheap fresh seed on startup; will be overwritten by new_run()
	run_seed = randi()
	_load_codex()


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
	run_seed = randi()
	# Reset super-weapon state — player._ready will repopulate via the
	# equipped Smart Bomb's apply().
	super_charges = 0
	max_super_charges = 3

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
