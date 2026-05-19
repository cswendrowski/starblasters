extends SceneTree

# Headless boot smoke test. Loads main.tscn, verifies autoloads, ticks the
# game long enough for the first wave to spawn, then asserts the scene tree
# is in a sane state. Prints a single SMOKE_RESULT line that smoke.ps1 greps.
#
# Exit codes:
#   0 — smoke passed
#   1 — smoke failed (the SMOKE_RESULT line says why)
#
# Tunables can be overridden via OS env vars: SMOKE_DURATION (default 5.0),
# SMOKE_LEVEL_PATH (default the level the main scene auto-builds).

const MAIN_SCENE := "res://scenes/main.tscn"
const DEFAULT_DURATION := 5.0
const SETTLE_TIME := 0.4
const EXPECTED_AUTOLOADS := ["/root/Run", "/root/Settings"]

var _failures: Array[String] = []
var _duration: float = DEFAULT_DURATION
var _waves_started: int = 0
var _enemies_spawned: int = 0


func _initialize() -> void:
	var env_dur := OS.get_environment("SMOKE_DURATION")
	if env_dur != "":
		var parsed := env_dur.to_float()
		if parsed > 0.0:
			_duration = parsed
	_run.call_deferred()


func _run() -> void:
	# Autoload check first — if Run/Settings are missing, the rest is moot.
	for path in EXPECTED_AUTOLOADS:
		if root.get_node_or_null(path) == null:
			_fail("missing autoload %s" % path)

	if not _failures.is_empty():
		_finish()
		return

	# Boot the main scene.
	var ps: PackedScene = load(MAIN_SCENE)
	if ps == null:
		_fail("could not load %s" % MAIN_SCENE)
		_finish()
		return

	var inst: Node = ps.instantiate()
	if inst == null:
		_fail("could not instantiate %s" % MAIN_SCENE)
		_finish()
		return
	root.add_child(inst)

	# Give the scene a moment to wire signals + autoloads.
	await create_timer(SETTLE_TIME).timeout

	# Expect a Player node somewhere under main. The exact path varies as
	# the scene evolves, so search the tree rather than hard-code a path.
	var player := _find_node_with_method(inst, "take_damage")
	if player == null:
		_fail("no Player node (no take_damage method) under main scene")

	# Expect a Director — search by method.
	var director := _find_node_with_method(inst, "start_level")
	if director == null:
		_fail("no Director node (no start_level method) under main scene")
	else:
		# Wire signal probes so we don't have to know internal field names.
		if director.has_signal("wave_started"):
			director.wave_started.connect(func(_i, _c, _s, _t): _waves_started += 1)
		if director.has_signal("enemy_spawned"):
			director.enemy_spawned.connect(func(_p, _b): _enemies_spawned += 1)

	# Tick the configured duration; the first wave should spawn within that.
	await create_timer(_duration).timeout

	# Healthy outcomes after the tick window:
	#  - a wave_started signal fired, OR
	#  - an enemy_spawned signal fired, OR
	#  - enemies are present in the group (in case signals were missed).
	var enemy_count := get_nodes_in_group("enemies").size()
	if _waves_started == 0 and _enemies_spawned == 0 and enemy_count == 0:
		_fail("no wave_started, no enemy_spawned, no enemies-in-group after %.1fs" % _duration)

	# Player should still be valid (didn't die from null-pointer during boot).
	if player != null and not is_instance_valid(player):
		_fail("Player node became invalid during smoke window")

	inst.queue_free()
	_finish()


func _find_node_with_method(root_node: Node, method: String) -> Node:
	if root_node.has_method(method):
		return root_node
	for child in root_node.get_children():
		var hit := _find_node_with_method(child, method)
		if hit:
			return hit
	return null


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE_RESULT: pass (duration=%.1fs waves=%d enemies=%d)" % [_duration, _waves_started, _enemies_spawned])
		quit(0)
	else:
		print("SMOKE_RESULT: fail")
		for f in _failures:
			print("SMOKE_FAIL: %s" % f)
		quit(1)
