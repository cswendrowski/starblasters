extends SceneTree

# Headless check for the unified RecycleController (recycling roster migration, 2026-06-29).
# Two parts:
#   1) resolve() — the offscreen DECISION, asserted against a matrix of (mode, position) cases
#      that mirror the old per-mode logic in enemy_base._offscreen_cleanup_check.
#   2) recycle() — a full fly-back on a REAL enemy_core scene (the Dart): assert is_recycling()
#      toggles, the firing/monitorable/outline get suspended + restored, the ghost material swap
#      (depth-tint) is applied + restored, and scale/visibility come back.
#
# Disk-safe: it mutates the in-memory config cache (config() returns it by reference) and
# invalidate()s at the end, so it never writes user://tuners/recycle.json (Roman's tuned file).
#
# Run: godot --headless -s tools/test_recycle.gd

const RC = preload("res://scripts/effects/recycle_controller.gd")
const DART := "res://scenes/enemies/core/enemy_core_s_dart.tscn"

var _fails := 0
var _started := false
var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	if not _started:
		_started = true
		_run_all()   # async; sets _done when finished (awaits let timers/tweens tick)
	return _done


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  ", msg)
	else:
		_fails += 1
		print("  FAIL  ", msg)


func _run_all() -> void:
	_test_resolve()
	await _test_recycle()
	_test_wreck()
	_test_turret_suspend()
	print("------")
	if _fails == 0:
		print("VERDICT: PASS")
	else:
		print("VERDICT: FAIL (", _fails, " failed)")
	_done = true
	quit(1 if _fails > 0 else 0)


# --- Part 1: resolve() decision matrix -------------------------------------

func _test_resolve() -> void:
	print("resolve() decision matrix:")
	var e = load(DART).instantiate()
	get_root().add_child(e)
	# A roomy fake viewport bound so the cases below are unambiguous regardless of headless size.
	var sz: Vector2 = e.get_viewport_rect().size
	var m: float = e.offscreen_margin
	var inside := Vector2(sz.x * 0.5, sz.y * 0.5)
	var below := Vector2(sz.x * 0.5, sz.y + m + 20.0)
	var above := Vector2(sz.x * 0.5, -m - 20.0)
	var off_left := Vector2(-m - 20.0, sz.y * 0.5)

	# CYCLE_BOTTOM
	e.offscreen_mode = e.OffscreenMode.CYCLE_BOTTOM
	e.allow_side_exit = false
	e._entered_playfield = true
	e.global_position = inside
	_check(RC.resolve(e) == RC.Action.IGNORE, "CYCLE_BOTTOM on-screen → IGNORE")
	e.global_position = below
	_check(RC.resolve(e) == RC.Action.RECYCLE, "CYCLE_BOTTOM below bottom → RECYCLE")
	e.global_position = above
	_check(RC.resolve(e) == RC.Action.IGNORE, "CYCLE_BOTTOM above top → IGNORE (no top trigger)")
	e.global_position = off_left
	_check(RC.resolve(e) == RC.Action.IGNORE, "CYCLE_BOTTOM off-side, no allow_side_exit → IGNORE")
	e.allow_side_exit = true
	_check(RC.resolve(e) == RC.Action.RECYCLE, "CYCLE_BOTTOM off-side + allow_side_exit → RECYCLE")

	# FREE_ANY_EDGE
	e.offscreen_mode = e.OffscreenMode.FREE_ANY_EDGE
	e.global_position = below
	_check(RC.resolve(e) == RC.Action.FREE, "FREE_ANY_EDGE below bottom → FREE")
	e.global_position = off_left
	_check(RC.resolve(e) == RC.Action.FREE, "FREE_ANY_EDGE off-side → FREE")
	e.global_position = above
	e._entered_playfield = true
	_check(RC.resolve(e) == RC.Action.FREE, "FREE_ANY_EDGE above top after entry → FREE")
	e._entered_playfield = false
	_check(RC.resolve(e) == RC.Action.IGNORE, "FREE_ANY_EDGE above top before entry → IGNORE")

	# FREE_OPPOSITE_SIDE
	e.offscreen_mode = e.OffscreenMode.FREE_OPPOSITE_SIDE
	e.global_position = off_left
	_check(RC.resolve(e) == RC.Action.FREE, "FREE_OPPOSITE_SIDE off-side → FREE")
	e.global_position = below
	_check(RC.resolve(e) == RC.Action.IGNORE, "FREE_OPPOSITE_SIDE below bottom → IGNORE (sides only)")

	# NONE + dying
	e.offscreen_mode = e.OffscreenMode.NONE
	e.global_position = below
	_check(RC.resolve(e) == RC.Action.IGNORE, "NONE → IGNORE")
	e.offscreen_mode = e.OffscreenMode.CYCLE_BOTTOM
	e._dying = true
	_check(RC.resolve(e) == RC.Action.IGNORE, "_dying → IGNORE")

	e.free()


# --- Part 2: a full recycle() fly-back -------------------------------------

func _test_recycle() -> void:
	print("recycle() full fly-back:")
	# Mutate the in-memory config to tiny timings (config() returns the cache by reference) so the
	# cycle completes fast. invalidate() at the end restores disk-backed behavior — no file written.
	RC.invalidate()
	var cfg: Dictionary = RC.config()
	cfg["hold_min"] = 0.01
	cfg["hold_max"] = 0.02
	cfg["fly_time"] = 0.3   # long enough to reliably sample the mid-fly state below

	var e = load(DART).instantiate()
	get_root().add_child(e)
	# No start() → no movement pattern, so the Dart's own _process won't auto-trigger; we drive
	# recycle() directly. Park it on-screen first.
	e.position = Vector2(e.screensize.x * 0.5, e.screensize.y * 0.4)
	var body := e.get_node_or_null("Sprite2D") as Sprite2D
	var orig_mat: Material = body.material if body != null else null
	var orig_scale: Vector2 = e.scale

	_check(not e.is_recycling(), "not recycling before the call")
	RC.recycle(e)   # fire-and-forget; runs synchronously up to the first await
	_check(e.is_recycling(), "is_recycling() true immediately after recycle()")

	# Sample mid-fly (past the ≤0.02s hold, well inside the 0.3s tween). monitorable is dropped via
	# set_deferred + the ghost material is stashed only after the hold await, so these can't be
	# checked synchronously — that's why they're sampled here, not right after the call.
	await create_timer(0.08).timeout
	if is_instance_valid(e):
		_check(e.is_recycling(), "is_recycling() still true mid-fly")
		_check(not e.monitorable, "monitorable dropped during cycle")
		if body != null:
			_check(e.has_meta("_recycle_prev_mat"), "ghost material stashed during cycle")

	# Let the rest of the cycle finish (0.3s fly + slack).
	await create_timer(0.4).timeout
	if not is_instance_valid(e):
		_check(false, "enemy survived the cycle")
		return

	_check(not e.is_recycling(), "is_recycling() false after the cycle")
	_check(e.visible, "visible restored after the cycle")
	_check(e.scale == orig_scale, "scale restored after the cycle")
	_check(e.monitorable, "monitorable restored after the cycle")
	if body != null:
		_check(not e.has_meta("_recycle_prev_mat"), "ghost material meta cleared")
		_check(body.material == orig_mat, "body material restored to original")
	e.free()
	RC.invalidate()   # drop the tiny in-memory config; next real run reloads from disk


# --- Part 3: the disabled-wreck recede look (shared with the recycler) ------

func _test_wreck() -> void:
	print("disabled-wreck recede look (shared MidDepthPresentation.recede_body):")
	# A wreck layer (group "wreck_layer") + Run meta "disable_deaths" route a kill into _die_as_wreck.
	var wlayer := Node2D.new()
	wlayer.add_to_group("wreck_layer")
	get_root().add_child(wlayer)
	var run = get_root().get_node_or_null("Run")
	if run == null:
		run = load("res://scripts/autoload/run_state.gd").new()
		run.name = "Run"
		get_root().add_child(run)
	run.set_meta("disable_deaths", true)

	var e = load(DART).instantiate()
	get_root().add_child(e)
	e.position = Vector2(e.screensize.x * 0.5, e.screensize.y * 0.4)
	e.has_ship_vfx = true   # ensure it qualifies for the general-disable wreck path
	e.is_hazard = false
	var body := e.get_node_or_null("Sprite2D") as Sprite2D
	_check(body != null, "dart has a body sprite")
	e.explode()   # disable path → _die_as_wreck: synchronous reparent + recede_body + WreckDrift attach
	_check(is_instance_valid(body) and body.get_parent() == wlayer, "wreck hull reparented into wreck layer")
	_check(body != null and body.material is ShaderMaterial, "wreck body got the shared depth-tint material")
	_check(body != null and body.get_node_or_null("WreckDrift") != null, "WreckDrift attached to the hull")
	run.remove_meta("disable_deaths")


# --- Part 4: turrets hold fire while their host recycles --------------------

func _test_turret_suspend() -> void:
	print("EnemyTurret holds fire while its host recycles/dies:")
	var host = load(DART).instantiate()
	get_root().add_child(host)
	var t := EnemyTurret.new()
	host.add_child(t)
	host._cycling = false
	host._dying = false
	_check(not t._host_suspended(), "turret active when host is live")
	host._cycling = true
	_check(t._host_suspended(), "turret suspended when host is recycling")
	host._cycling = false
	host._dying = true
	_check(t._host_suspended(), "turret suspended when host is dying")
	host._dying = false

	# Nested: a turret on a sub-part (plain node) whose RECYCLING core is higher up the chain.
	var part := Node2D.new()
	host.add_child(part)
	var t2 := EnemyTurret.new()
	part.add_child(t2)
	host._cycling = true
	_check(t2._host_suspended(), "sub-part turret sees the recycling core above it")
	host._cycling = false
	_check(not t2._host_suspended(), "sub-part turret clear when core is live")
	host.free()
