extends Node2D
## Draw-index crash repro harness (2026-06-22).
##
## Isolates the hypothesised root cause of the intermittent native crash:
##     ERROR: Parameter "canvas_item" is null
##     at canvas_item_set_draw_index (servers/rendering/renderer_canvas_cull.cpp:1917)
## often escalating to SIGSEGV.
##
## HYPOTHESIS (finding #1 of the 2026-06-22 review): the trigger is ABSOLUTE-Z
## (`z_as_relative = false`) CanvasItems — engine-trail Line2Ds, death-dust + debris
## sprites — that live as SIBLINGS at the shared combat root and FREE during the enemy
## death frame. That is the exact shape the team already blamed for the reverted
## ShipDebrisEmber race (see enemy_base.gd:516-518), but its surviving twins
## (engine_trail_fx / death_dust / _spawn_debris) are live on EVERY enemy death.
##
## WHY THIS HARNESS LOOKS THE WAY IT DOES:
##   - It does NOT change scenes. The change_scene/backdrop-teardown theory was a dead
##     end; this stays in one scene and hammers the per-death churn instead.
##   - It keeps a DENSE crowd of real engine-trail enemies alive at a shared Node2D root
##     (== the production `Main` spawn parent), so that root carries many absolute-z
##     Line2D/sprite siblings at once.
##   - It then kills them ONE AT A TIME (the "kill any enemy in any POI" signal) and in
##     periodic MASS WIPES (the wave-clear / smart-bomb burst), over and over.
##   - It populates the real asteroid-field backdrop (the "loading an asteroid POI"
##     signal) for a faithful, dense baseline canvas.
##
## IT MUST RUN ON THE REAL FORWARD+ RENDERER, WINDOWED. Headless uses the dummy
## renderer, which skips the canvas path entirely and CANNOT fault.
##     tools\repro_draw_index_crash.ps1
##
## Log: user://draw_index_crash.log (flushed per line). If the process dies, the log's
## last line tells you how many kills survived before the crash. Esc aborts cleanly.

const ENEMY_SCENE := "res://scenes/enemies/core/enemy_core_s_dart.tscn"  # has Engine* markers → trails
const BACKDROP_SCENE := "res://scenes/parallax/backdrop_coordinator.tscn"
const LOG_PATH := "user://draw_index_crash.log"
const Playfield = preload("res://scripts/systems/playfield.gd")

# --- Tunables (Roman: crank these to make the race more likely) ----------------
const CROWD := 30                    # steady-state live enemies held at the shared root
const SINGLE_KILL_INTERVAL := 6      # frames between single kills (~0.1s @ 60fps)
const MASS_WIPE_EVERY := 40          # do a full wipe every N single kills
const WIPE_SETTLE_FRAMES := 45       # frames to let the 0.5s death timers + trail frees flush
const TRAIL_WARMUP_FRAMES := 60      # let the first crowd's trails populate before killing
const TOTAL_KILLS := 50000           # hard cap (effectively "run until crash or Esc")
const WITH_BACKDROP := true          # populate the asteroid-field backdrop for canvas density
const HEARTBEAT_EVERY := 25          # log a running count every N kills

var _crowd := CROWD
var _kills := 0
var _aborted := false
var _log: FileAccess = null
var _backdrop: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	_open_log()
	if DisplayServer.get_name() == "headless":
		_logln("!!! HEADLESS DISPLAY — the canvas crash CANNOT reproduce here.")
		_logln("!!! Launch WINDOWED via tools\\repro_draw_index_crash.ps1 (real Forward+ renderer).")
	var has_rd := RenderingServer.get_rendering_device() != null
	_logln("=== DRAW-INDEX CRASH REPRO START ===")
	_logln("display=%s  rendering_device=%s  crowd=%d  with_backdrop=%s" % [
		DisplayServer.get_name(), str(has_rd), _crowd, str(WITH_BACKDROP)])
	_configure_run_asteroid()
	if WITH_BACKDROP:
		_add_backdrop()
	_run()


# Drive Run into an asteroid-field hazard POI so the backdrop populates a dense,
# shader-heavy decorative asteroid field (the "loading an asteroid POI" signal).
func _configure_run_asteroid() -> void:
	if not has_node("/root/Run"):
		_logln("WARN: no /root/Run autoload — backdrop will use defaults")
		return
	var run = get_node("/root/Run")
	if run.has_method("new_run"):
		run.new_run()
	if "run_seed" in run:
		run.run_seed = 1337
	if "test_mode_active" in run:
		run.test_mode_active = true
	if "sectors_cleared" in run:
		run.sectors_cleared = 3          # depth scaling, denser death VFX
	if "current_node_type" in run:
		run.current_node_type = 5        # HAZARD
	if "current_hazard_subtype" in run:
		run.current_hazard_subtype = "asteroid_field"
	if "current_stellar" in run:
		run.current_stellar = {
			"has_asteroids": true,
			"asteroid_density": 0.7,
			"planet_idx": 2,
		}


# Instance the real combat backdrop as a child of THIS root (mirrors main.tscn's
# "Backdrop" child). Added before any enemies, so it sits at index 0; its CanvasLayers
# render their own canvases. Run.current_stellar is already set, so its _ready→_populate
# rolls the asteroid field.
func _add_backdrop() -> void:
	var ps: PackedScene = load(BACKDROP_SCENE)
	if ps == null:
		_logln("WARN: backdrop scene failed to load: %s" % BACKDROP_SCENE)
		return
	_backdrop = ps.instantiate()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	_logln("backdrop populated (asteroid field)")


func _run() -> void:
	await get_tree().process_frame
	_fill_crowd()
	_logln("crowd filled to %d, warming up trails (%d frames)..." % [_alive(), TRAIL_WARMUP_FRAMES])
	await _wait_frames(TRAIL_WARMUP_FRAMES)

	var since_wipe := 0
	while not _aborted and _kills < TOTAL_KILLS:
		_fill_crowd()
		# Single kill — the "kill any enemy in any POI" path, fired into a dense canvas.
		if _kill_one():
			_kills += 1
			since_wipe += 1
			if _kills % HEARTBEAT_EVERY == 0:
				_logln("kills=%d  alive=%d" % [_kills, _alive()])
		await _wait_frames(SINGLE_KILL_INTERVAL)
		if _aborted:
			break
		# Periodic MASS WIPE — the wave-clear / smart-bomb burst: dozens of absolute-z
		# trail/dust/debris frees in one flush.
		if since_wipe >= MASS_WIPE_EVERY:
			since_wipe = 0
			var n := _kill_all()
			_kills += n
			_logln("MASS WIPE: %d killed at once (kills=%d, alive=%d)" % [n, _kills, _alive()])
			await _wait_frames(WIPE_SETTLE_FRAMES)

	if _aborted:
		_logln("=== ABORTED at %d kills — NO CRASH ===" % _kills)
	else:
		_logln("=== COMPLETED %d kills — NO CRASH ===" % _kills)
	_close_log()
	get_tree().quit()


func _fill_crowd() -> void:
	var guard := 0
	while _alive() < _crowd and guard < _crowd:
		_spawn_one()
		guard += 1


func _spawn_one() -> void:
	var ps: PackedScene = load(ENEMY_SCENE)
	if ps == null:
		return
	var e = ps.instantiate()
	if e is Node2D:
		# Spawn across the upper playfield band so downward movement keeps them on
		# screen for ~1s+ (long enough for engine trails to streak) before a kill.
		(e as Node2D).position = Vector2(
			randf_range(Playfield.X_MIN + 12.0, Playfield.X_MAX - 12.0),
			randf_range(16.0, 70.0))
	add_child(e)


# Kill one random live enemy via the production take_hit path (drives the real
# explode() → dust/debris/trail-free death frame). Returns true if one was killed.
func _kill_one() -> bool:
	var live := get_tree().get_nodes_in_group("enemies")
	if live.is_empty():
		return false
	# Filter to valid, non-dying nodes that can take a hit.
	var candidates: Array = []
	for n in live:
		if n != null and is_instance_valid(n) and n.has_method("take_hit"):
			candidates.append(n)
	if candidates.is_empty():
		return false
	var victim = candidates[randi() % candidates.size()]
	victim.take_hit(99999)
	return true


# Kill every live enemy in the same frame (the burst path). Returns the count hit.
func _kill_all() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != null and is_instance_valid(e) and e.has_method("take_hit"):
			e.take_hit(99999)
			n += 1
	return n


func _alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _wait_frames(n: int) -> void:
	for _i in n:
		if Input.is_key_pressed(KEY_ESCAPE):
			_aborted = true
			return
		await get_tree().process_frame


# Optional override from the launcher: `... ++ --crowd 50`
func _parse_args() -> void:
	var ua := OS.get_cmdline_user_args()
	for i in ua.size():
		if ua[i] == "--crowd" and i + 1 < ua.size():
			_crowd = maxi(1, int(ua[i + 1]))


func _open_log() -> void:
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)


func _logln(s: String) -> void:
	print("[di_crash] ", s)
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _close_log() -> void:
	if _log != null:
		_log.close()
		_log = null
