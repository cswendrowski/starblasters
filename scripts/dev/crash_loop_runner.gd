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
const ShipDamageTellsScript = preload("res://scripts/effects/ship_damage_tells.gd")
# Ship enemies (enemy_core → has_ship_vfx → the damage tells attach). Batch-spawned in a crowd
# and wiped at once, because the wave director only trickles 1-2 on screen — no mass death.
const ENEMY_SCENES := [
	"res://scenes/enemies/core/enemy_core_s_dart.tscn",
]

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
	# Re-enable the LIVE per-enemy damage tells (default-off, reverted as the prime crash
	# suspect) for this run — the spark/burn render nodes + the draw-index race on enemy death.
	ShipDamageTellsScript.live_enabled = true
	_logln("live damage tells ON + full backdrop teardown per load")
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
		# Full teardown like the live transition: unlink + free the LEAVING combat's backdrop
		# BEFORE the swap (mirrors SceneTransition's on_covered teardown — the canvas-reindex /
		# pipeline crashes live in this teardown+rebuild seam), then rebuild fresh.
		var leaving := get_tree().current_scene
		if leaving != null and is_instance_valid(leaving):
			var bd := leaving.get_node_or_null("Backdrop")
			if bd != null and is_instance_valid(bd):
				leaving.remove_child(bd)
				bd.queue_free()
		get_tree().change_scene_to_file(COMBAT_SCENE)
		# Wait for the intro/fly-in to finish + the first wave to ACTUALLY spawn (poll the group,
		# up to ~8s), then slay repeatedly over a window. Many simultaneous deaths churn the
		# death-frame draw order where the ShipDamageTells / ShipDebrisEmber race lives.
		await _wait_frames(45)   # let combat + backdrop settle
		if _aborted:
			break
		# Keep a DENSE crowd of ship enemies and chip everyone 1-2 dmg each tick (~0.66s). This
		# ramps each ship through its damage-tell THRESHOLDS (spark -> burn -> disintegrate),
		# spawning render nodes progressively the whole time, then take_hit kills them at 0 HP.
		# Refill as they drop so the field keeps churning. That gradual escalation is where the
		# tell crash lives — a bare explode() bypasses it entirely.
		_spawn_crowd(24)
		var peak := 0
		for _tick in 18:
			await _wait_frames(40)
			if _aborted:
				break
			var alive := get_tree().get_nodes_in_group("enemies").size()
			peak = maxi(peak, alive)
			if alive < 18:
				_spawn_crowd(24 - alive)
			_damage_all(1 + randi() % 2)
		if _aborted:
			break
		_count = i + 1
		_logln("load %d/%d OK (peak %d alive, chipped to death)" % [_count, _iterations, peak])
	if _aborted:
		_logln("=== ABORTED after %d/%d loads (mode=%s) ===" % [_count, _iterations, tag])
	else:
		_logln("=== SURVIVED %d/%d loads (mode=%s) — NO CRASH ===" % [_count, _iterations, tag])
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if s.has_method("set_autofire"):
			s.set_autofire(_orig_autofire)
	ShipDamageTellsScript.live_enabled = false   # back to lab-only
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
	if randf() < 0.85:
		run.current_node_type = 0  # COMBAT (ship enemies — the tells only attach to ships)
		run.set_meta("forced_faction", randi() % 4)
	else:
		run.current_node_type = 5  # HAZARD (asteroid gameplay rocks + chunk path)
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


# Batch-spawn `n` ship enemies directly into the combat scene, scattered across the playfield.
# They self-register in the "enemies" group + attach the damage tells in _ready (deferred), so a
# following _slay_enemies() explodes the whole crowd at once.
func _spawn_crowd(n: int) -> void:
	var host := get_tree().current_scene
	if host == null or not is_instance_valid(host):
		return
	for i in n:
		var ps := load(ENEMY_SCENES[i % ENEMY_SCENES.size()]) as PackedScene
		if ps == null:
			continue
		var e = ps.instantiate()
		if e is Node2D:
			(e as Node2D).position = Vector2(randf_range(140.0, 340.0), randf_range(20.0, 140.0))
		host.add_child(e)
		# Beef HP so 1-2 dmg/tick WALKS the ship through its tell thresholds (spark -> burn ->
		# disintegrate) over several ticks instead of one-shotting past them.
		if "max_health" in e:
			e.max_health = 16
		if "health" in e:
			e.health = 16


# Poll until the first wave actually exists (the intro/fly-in delays it), up to cap_frames.
# Returns the live enemy count seen.
func _wait_for_enemies(cap_frames: int) -> int:
	var waited := 0
	while waited < cap_frames:
		if Input.is_key_pressed(KEY_ESCAPE):
			_aborted = true
			return 0
		var c := get_tree().get_nodes_in_group("enemies").size()
		if c > 0:
			return c
		await get_tree().process_frame
		waited += 1
	return get_tree().get_nodes_in_group("enemies").size()


# Chip every live enemy by `amount` (1-2). take_hit drives set_damage across the tell thresholds
# (spark/burn render nodes spawn progressively) and kills the ship NATURALLY at 0 HP — so the
# tells actually escalate, unlike a bare explode() which skips the whole ramp.
func _damage_all(amount: int) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n != null and is_instance_valid(n) and n.has_method("take_hit"):
			n.take_hit(amount)


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
