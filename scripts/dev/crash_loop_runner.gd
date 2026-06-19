extends Node
## Persistent crash-loop runner (Roman 2026-06-19) for the #116172 combat-load pipeline SIGSEGV.
## Added to get_tree().root so it SURVIVES change_scene. Reloads an asteroid-POI combat N times,
## logging each survived load to BOTH stdout ("[crash_loop] ...") and user://crash_loop.log
## (flushed per line). If a load SIGSEGVs the process dies — the log's last line is then the
## number of loads that survived before the crash. A/B: run LIVE (live Asteroids.gdshader present,
## should crash) vs BAKED (no live asteroid shader, should survive).
##
## Each load varies the backdrop planet so new backdrop shader variants must compile — the
## cold-compile burst the crash lives in (the cache misses per-load per the d3d12/vulkan traces).
## Esc aborts.

const COMBAT_SCENE := "res://scenes/main.tscn"
const DEV_MENU_SCENE := "res://scenes/dev_menu.tscn"
const LOG_PATH := "user://crash_loop.log"
const WAIT_FRAMES := 180   # ~3s/load — load + backdrop + a wave spawns + BOTH sides fire (max burst)
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _mode_baked: bool = false
var _iterations: int = 50
var _count: int = 0
var _aborted: bool = false
var _log: FileAccess = null
var _orig_autofire: bool = false


func start(baked: bool, iterations: int) -> void:
	_mode_baked = baked
	_iterations = maxi(1, iterations)
	_run()


func _run() -> void:
	var tag := "BAKED" if _mode_baked else "LIVE"
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)   # fresh log each run
	_logln("=== CRASH LOOP START  mode=%s  iterations=%d ===" % [tag, _iterations])
	# Auto-fire ON for the run so the player fires every load → its weapon/bullet/muzzle shaders
	# compile too (saved + restored at the end). Enemies fire at the idle player regardless.
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		_orig_autofire = bool(s.autofire) if "autofire" in s else false
		if s.has_method("set_autofire"):
			s.set_autofire(true)
	# Bake the shared atlas once up front (baked mode) so each combat load reuses the cache
	# instead of re-baking. This IS the load-time bake the production loading screen would cover.
	AsteroidBakeCache.enabled = _mode_baked
	if _mode_baked:
		_logln("baking atlas...")
		await AsteroidBakeCache.ensure_baked(self)
		_logln("atlas baked, ready=%s" % str(AsteroidBakeCache.is_ready()))
	for i in _iterations:
		if _aborted:
			break
		_configure_run()
		get_tree().change_scene_to_file(COMBAT_SCENE)
		await _wait_frames(WAIT_FRAMES)
		if _aborted:
			break
		_count = i + 1
		_logln("load %d/%d OK" % [_count, _iterations])
	if _aborted:
		_logln("=== ABORTED after %d/%d loads (mode=%s) ===" % [_count, _iterations, tag])
	else:
		_logln("=== SURVIVED %d/%d loads (mode=%s) — NO CRASH ===" % [_count, _iterations, tag])
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if s.has_method("set_autofire"):
			s.set_autofire(_orig_autofire)
	if _log != null:
		_log.close()
		_log = null
	AsteroidBakeCache.enabled = false
	get_tree().change_scene_to_file(DEV_MENU_SCENE)
	queue_free()


# Configure Run for an asteroid-field hazard POI (the crashing scenario), varying the backdrop
# planet each load to force fresh backdrop shader variants.
func _configure_run() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	run.new_run()
	run.run_seed = randi()                  # re-roll the whole wave / enemy / weapon set each load
	run.test_mode_active = true
	run.sectors_cleared = 2 + randi() % 6   # depth 2-7 → more enemies + weapon/component variety
	run.combats_in_sector = randi() % 3
	# Alternate big faction-combat POIs (max enemy/weapon shader burst) with asteroid-hazard POIs
	# (gameplay rocks + chunks). BOTH carry the asteroid backdrop (has_asteroids), so LIVE always
	# still has the live Asteroids.gdshader to remove — the A/B stays meaningful either way.
	if randf() < 0.5:
		run.current_node_type = 0  # COMBAT
		run.set_meta("forced_faction", randi() % 4)
	else:
		run.current_node_type = 5  # HAZARD
		run.current_hazard_subtype = "asteroid_field"
	var st := {}
	st["has_asteroids"] = true
	st["asteroid_density"] = 0.7
	st["planet_idx"] = randi() % 6   # vary the backdrop planet → fresh backdrop shader variants
	run.current_stellar = st
	# Arm the player so its weapon/bullet/muzzle shaders compile too (autofire is on for the run).
	var cannon = PartCatalog._make_by_name("_make_basic_blaster", SlotTypes.SlotType.CANNON)
	if cannon != null:
		run.equip_part(cannon)


func _wait_frames(n: int) -> void:
	for _i in n:
		if Input.is_key_pressed(KEY_ESCAPE):
			_aborted = true
			return
		await get_tree().process_frame


func _logln(s: String) -> void:
	print("[crash_loop] ", s)
	if _log != null:
		_log.store_line(s)
		_log.flush()
