extends Node
## Draw-index crash repro — HIGH-FIDELITY AUTO-PLAYER (2026-06-22).
##
## Plays the game as close to a real player as a headless-safe harness can, on a loop,
## hunting:  ERROR: Parameter "canvas_item" is null  at canvas_item_set_draw_index → SIGSEGV.
##
## Each level it:
##   - Rolls a RANDOM realistic loadout (primary cannon + secondary wing weapon + smart-bomb
##     device + sometimes a swapped shift-mode / module / engine, random Marks) on top of the
##     run defaults (focus + shield core + basic engine/blaster).
##   - Enters combat through the REAL load path: LevelLauncher.go() → loading screen (threaded
##     preload) → fly-off → change_scene_packed(cover_only) → main's own intro. (The user's #1
##     repro signal is "loading a combat level" — so we load it the way the game does.)
##   - Drives a VULNERABLE player (NOT invincible) that sweeps the whole playfield, holds primary
##     + secondary fire, periodically swaps weapons, pulses nose fire, and ducks into focus — so
##     shields, hull damage-tells, i-frames, weapon-swap churn, and the smart-bomb death-bomb all
##     actually run. The player can DIE.
##   - On player death OR level clear, main runs its real sequence (death VFX + call_group enemy
##     wipe, or fly-off + fade). As soon as the scene leaves combat we skip the summary/map and
##     LevelLauncher.go() straight into a fresh random level.
##
## MUST RUN WINDOWED on real Forward+ (headless dummy renderer can't fault):
##     tools\repro_draw_index_combat.bat
## Log: user://draw_index_combat.log (flushed per line) — last line = how far it got + the build.
## Esc aborts cleanly.

const COMBAT_SCENE := "res://scenes/main.tscn"
const LOG_PATH := "user://draw_index_combat.log"
const Playfield = preload("res://scripts/systems/playfield.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const LevelLauncher = preload("res://scripts/systems/level_launcher.gd")
const ShipDamageTells = preload("res://scripts/effects/ship_damage_tells.gd")

# Flip ON to re-enable the reverted per-enemy damage tells (spark/burn/ember on enemy death) and
# test whether they reproduce the old "canvas draw-order race on enemy death" crash. Default-off so
# the harness's primary job (the swap crash, now fixed) stays clean.
const ENABLE_DAMAGE_TELLS := false

# --- Loadout pools (by slot) ---------------------------------------------------
const PRIMARY_FACTORIES := ["_make_basic_blaster", "_make_heavy_blaster", "_make_twin_blaster",
	"_make_autocannon", "_make_minigun", "_make_rotary_laser", "_make_quad_lasers", "_make_wave_gun",
	"_make_laser_beam", "_make_spread_cannon", "_make_shredder", "_make_pulse_laser"]
const SECONDARY_FACTORIES := ["_make_rocket_pod", "_make_seeking_missile", "_make_anti_ship_missile",
	"_make_particle_beam", "_make_drone_swarm", "_make_swarm_launcher"]
const MODULE_FACTORIES := ["_make_overcharge_core", "_make_siphon_core", "_make_repair_nanites",
	"_make_ablative_plating", "_make_targeting_computer", "_make_overclock_core", "_make_reinforced_hull",
	"_make_thrusters", "_make_shield_capacitor", "_make_intercept_drones", "_make_backup_shield_capacitor",
	"_make_reflective_shield", "_make_micro_fabricator", "_make_energy_routers", "_make_side_pods"]
const SHIFT_FACTORIES := ["_make_phase_shift", "_make_hyper_mode"]   # focus is the default
const ENGINE_FACTORIES := ["_make_basic_engine", "_make_vectoring_engine"]

# --- Tunables ------------------------------------------------------------------
const LEVEL_CAP := 500          # max levels (effectively "until crash or Esc")
const LEVEL_TIMEOUT := 9000     # frames per level before forcing the next (~150s safety)
const COMBAT_WAIT := 900        # max frames to wait for combat to come up after go() (~15s)
const SETTLE_AFTER_LEVEL := 20  # frames between a level ending and relaunching
const HEARTBEAT_FRAMES := 180   # log a heartbeat every ~3s
const MOVE_DEADZONE := 4.0
const PLAY_Y_MIN := 24.0        # full playfield sweep band (viewport is 270 tall)
const PLAY_Y_MAX := 250.0
const TARGET_DWELL_MIN := 14
const TARGET_DWELL_MAX := 40
const SWAP_INTERVAL := 150      # frames between primary-swap pulses
const NOSE_INTERVAL := 90       # frames between nose-fire pulses
const FOCUS_PERIOD := 300       # focus-window cadence
const FOCUS_FOR := 90           # frames focus is held per window
const ALL_ACTIONS := ["left", "right", "up", "down", "shoot", "shoot2", "shoot_nose", "focus", "primary_swap"]

var _is_driver := false
var _aborted := false
var _log: FileAccess = null
var _target := Vector2.ZERO
var _target_dwell := 0
var _poi_desc := ""
var _ship_variant := 0


func _ready() -> void:
	if _is_driver:
		_drive()
	else:
		_bootstrap()


func _bootstrap() -> void:
	var d := Node.new()
	d.set_script(get_script())
	d.set("_is_driver", true)
	d.name = "DrawIndexCombatDriver"
	# Deferred: during the booted scene's _ready the root is mid-setup ("parent busy").
	get_tree().root.add_child.call_deferred(d)


func _drive() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_log()
	if DisplayServer.get_name() == "headless":
		_logln("!!! HEADLESS — the canvas crash CANNOT reproduce here. Run windowed.")
	_logln("=== DRAW-INDEX HIGH-FIDELITY AUTO-PLAYER START ===")
	_logln("display=%s  rendering_device=%s" % [
		DisplayServer.get_name(), str(RenderingServer.get_rendering_device() != null)])
	_enable_autofire()
	if ENABLE_DAMAGE_TELLS:
		ShipDamageTells.force_live = true
		_logln("ShipDamageTells.force_live = TRUE (damage-tell death-frame repro test)")

	var level := 0
	while not _aborted and level < LEVEL_CAP:
		level += 1
		var build := _setup_run()
		_logln("LEVEL %d: launch [%s] ship=%s  build=[%s]" % [level, _poi_desc, ["A","B","C"][_ship_variant] if _ship_variant < 3 else str(_ship_variant), build])
		# Real load path — fire-and-forget coroutine that survives the scene swaps.
		LevelLauncher.go(get_tree(), COMBAT_SCENE)
		if not await _wait_until_combat():
			_logln("LEVEL %d: combat never came up (aborted=%s) — retry" % [level, str(_aborted)])
			if _aborted:
				break
			continue
		_logln("LEVEL %d: combat live [%s]" % [level, _poi_desc])

		var frames := 0
		_pick_target()
		while not _aborted and frames < LEVEL_TIMEOUT:
			var host := _combat()
			if not _is_combat(host):
				break   # player died → summary, or level cleared → outro swapped the scene
			_drive_player_full(host, frames)
			if frames % HEARTBEAT_FRAMES == 0:
				_logln("L%d f%d alive=%d hull=%s" % [level, frames, _alive(), _player_hull(host)])
			frames += 1
			if _check_esc():
				break
			await get_tree().process_frame
		_release_all_input()
		_logln("LEVEL %d: ended at frame %d (died or cleared) — skipping summary, relaunching" % [level, frames])
		await _wait_frames(SETTLE_AFTER_LEVEL)

	if _aborted:
		_logln("=== ABORTED after %d levels — NO CRASH ===" % level)
	else:
		_logln("=== COMPLETED %d levels — NO CRASH ===" % level)
	_finish()


# new_run (defaults: focus + shield core + basic engine/blaster) → random POI → random loadout.
# Returns a short build description for the log.
func _setup_run() -> String:
	if not has_node("/root/Run"):
		_logln("WARN: no /root/Run autoload")
		return "?"
	var run = get_node("/root/Run")
	if run.has_method("new_run"):
		run.new_run()
	if "run_seed" in run:
		run.run_seed = randi()
	if "test_mode_active" in run:
		run.test_mode_active = true
	if "sectors_cleared" in run:
		run.sectors_cleared = 1 + randi() % 6
	# Force a NON-DEFAULT ship (B/C) every level. ship_variant != 0 makes main._install_chosen_player
	# do an IMMEDIATE player.free() + add_child + move_child at combat load — a synchronous CanvasItem
	# RID destruction + draw-order reindex that ship A (variant 0, what new_run resets to) NEVER runs.
	# This is the load-time path the harness has never exercised. (Divergence hunt, 2026-06-22.)
	var ship_variant := 1 + randi() % 2   # 1=B, 2=C
	_ship_variant = ship_variant
	if "ship_variant" in run:
		run.ship_variant = ship_variant
	var planet_idx := randi() % 6
	if randi() % 3 == 0:
		if "current_node_type" in run:
			run.current_node_type = 5            # HAZARD
		if "current_hazard_subtype" in run:
			run.current_hazard_subtype = "asteroid_field"
		if "current_stellar" in run:
			run.current_stellar = {"has_asteroids": true, "asteroid_density": 0.7, "planet_idx": planet_idx}
		_poi_desc = "asteroid_field"
	else:
		var faction := randi() % 4
		if "current_node_type" in run:
			run.current_node_type = 0            # COMBAT
		if "current_hazard_subtype" in run:
			run.current_hazard_subtype = ""
		if run.has_method("set_meta"):
			run.set_meta("forced_faction", faction)
		if "current_stellar" in run:
			run.current_stellar = {"planet_idx": planet_idx}
		_poi_desc = "combat f%d" % faction
	return _roll_loadout(run)


func _roll_loadout(run) -> String:
	var names: Array = []
	_equip(run, names, _pick(PRIMARY_FACTORIES), Slots.SlotType.CANNON)
	_equip(run, names, _pick(SECONDARY_FACTORIES), Slots.SlotType.HARDPOINT_WING)
	_equip(run, names, "_make_smart_bomb", Slots.SlotType.DEVICE_BAY_1)
	if randi() % 2 == 0:
		_equip(run, names, _pick(MODULE_FACTORIES), Slots.SlotType.MODULE)
	if randi() % 3 == 0:
		_equip(run, names, _pick(SHIFT_FACTORIES), Slots.SlotType.SHIFT_MODE)
	if randi() % 2 == 0:
		_equip(run, names, _pick(ENGINE_FACTORIES), Slots.SlotType.ENGINE)
	return ", ".join(names)


func _equip(run, names: Array, factory: String, slot: int) -> void:
	if not run.has_method("equip_part"):
		return
	var part = PartCatalog._make_by_name(factory, slot)
	if part == null:
		return
	if "mark" in part:
		part.mark = _rand_mark(part)
	run.equip_part(part)
	if "display_name" in part:
		names.append(part.display_name)


func _pick(pool: Array) -> String:
	return pool[randi() % pool.size()]


func _rand_mark(part) -> int:
	var m := 1 + randi() % 3
	if randi() % 4 == 0:
		m += randi() % 3
	var cap := int(part.max_mark) if "max_mark" in part else 9
	return clampi(m, 1, maxi(1, cap))


func _enable_autofire() -> void:
	if not has_node("/root/Settings"):
		return
	var s = get_node("/root/Settings")
	if s.has_method("set_autofire"):
		s.set_autofire(true)


func _wait_until_combat() -> bool:
	var waited := 0
	while waited < COMBAT_WAIT:
		if _check_esc():
			return false
		if _is_combat(_combat()):
			return true
		await get_tree().process_frame
		waited += 1
	return _is_combat(_combat())


func _combat() -> Node:
	return get_tree().current_scene


func _is_combat(host) -> bool:
	return host != null and is_instance_valid(host) and host.scene_file_path == COMBAT_SCENE


func _player(host):
	if host == null or not is_instance_valid(host):
		return null
	var p = host.get("player")
	if p == null or not is_instance_valid(p):
		p = host.find_child("Player", true, false)
	return p if (p != null and is_instance_valid(p) and p is Node2D) else null


func _player_hull(host) -> String:
	var p = _player(host)
	if p != null and "hull" in p:
		return str(p.hull)
	return "?"


# Vulnerable auto-pilot: sweep the full playfield, hold primary + secondary fire, pulse nose fire,
# periodically swap primary, and duck into focus — all via the real input actions.
func _drive_player_full(host, frames: int) -> void:
	var p = _player(host)
	if p == null:
		return
	var pos: Vector2 = (p as Node2D).global_position
	_target_dwell -= 1
	if _target_dwell <= 0 or pos.distance_to(_target) < 10.0:
		_pick_target()
	_axis("right", "left", _target.x - pos.x)
	_axis("down", "up", _target.y - pos.y)
	# Hold primary + secondary fire.
	_press("shoot")
	_press("shoot2")
	# Brief nose-fire pulses.
	var nph := frames % NOSE_INTERVAL
	if nph == 0:
		_press("shoot_nose")
	elif nph == 6:
		_release("shoot_nose")
	# Brief primary-swap pulses (cycles equipped primaries / smart-mount).
	var sph := frames % SWAP_INTERVAL
	if sph == 0:
		_press("primary_swap")
	elif sph == 4:
		_release("primary_swap")
	# Focus windows (engages the focus dot/trail + slow-move).
	var fph := frames % FOCUS_PERIOD
	if fph == 0:
		_press("focus")
	elif fph == FOCUS_FOR:
		_release("focus")


func _axis(pos_act: String, neg_act: String, delta: float) -> void:
	if delta > MOVE_DEADZONE:
		_press(pos_act)
		_release(neg_act)
	elif delta < -MOVE_DEADZONE:
		_press(neg_act)
		_release(pos_act)
	else:
		_release(pos_act)
		_release(neg_act)


func _pick_target() -> void:
	_target = Vector2(
		randf_range(Playfield.X_MIN + 10.0, Playfield.X_MAX - 10.0),
		randf_range(PLAY_Y_MIN, PLAY_Y_MAX))
	_target_dwell = randi_range(TARGET_DWELL_MIN, TARGET_DWELL_MAX)


func _press(action: String) -> void:
	if InputMap.has_action(action) and not Input.is_action_pressed(action):
		Input.action_press(action)


func _release(action: String) -> void:
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		Input.action_release(action)


func _release_all_input() -> void:
	for a in ALL_ACTIONS:
		_release(a)


func _alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _check_esc() -> bool:
	if Input.is_key_pressed(KEY_ESCAPE):
		_aborted = true
		return true
	return false


func _wait_frames(n: int) -> void:
	for _i in n:
		if _check_esc():
			return
		await get_tree().process_frame


func _finish() -> void:
	_release_all_input()
	ShipDamageTells.force_live = false   # drop the dev override (user setting still governs)
	_close_log()
	get_tree().quit()


func _open_log() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)


func _logln(s: String) -> void:
	print("[di_combat] ", s)
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _close_log() -> void:
	if _log != null:
		_log.close()
		_log = null
