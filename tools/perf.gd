extends SceneTree

# Performance harness. Boots a target scenario, samples Godot's Performance
# singleton each frame for SMOKE_DURATION seconds, and prints a single
# PERF_JSON line at the end that perf.ps1 parses.
#
# Scenarios are selected by the PERF_SCENARIO env var:
#   idle           — main.tscn, no input
#   first_wave     — main.tscn, ticked through first wave spawn window
#   bullet_stress  — main.tscn, then 200 bullet scenes force-spawned
#   boss           — main.tscn, fast-forwarded to boss spawn
#
# Sampling cadence: every frame, recorded into ring buffers. p50/p95/max
# computed at end.

const DEFAULT_DURATION := 5.0
const DEFAULT_SCENARIO := "first_wave"
# Wait this long after the scenario is built before sampling, so scene-load
# cost and first-wave spawn spikes don't dominate the p95.
const WARMUP_TIME := 1.5
const MAIN_SCENE := "res://scenes/main.tscn"
const BULLET_SCENE := "res://scenes/projectiles/projectile_ball.tscn"
const SETTLE_TIME := 0.4
const STRESS_BULLET_COUNT := 200

var _duration: float = DEFAULT_DURATION
var _scenario: String = DEFAULT_SCENARIO
var _frame_ms: Array[float] = []
var _node_counts: Array[int] = []
var _draw_calls: Array[int] = []
var _primitives: Array[int] = []
var _resource_counts: Array[int] = []
var _peak_mem: float = 0.0
var _start_time: float = 0.0
var _sampling: bool = false


func _initialize() -> void:
	var env_dur := OS.get_environment("PERF_DURATION")
	if env_dur != "":
		var parsed := env_dur.to_float()
		if parsed > 0.0:
			_duration = parsed
	var env_scn := OS.get_environment("PERF_SCENARIO")
	if env_scn != "":
		_scenario = env_scn
	_run.call_deferred()


func _run() -> void:
	var inst: Node = await _build_scenario(_scenario)
	if inst == null:
		print("PERF_JSON: {\"error\":\"could not build scenario %s\"}" % _scenario)
		quit(1)
		return

	# Warmup window — discard the first WARMUP_TIME seconds so scene-load
	# and first-wave-spawn spikes don't dominate p95.
	await create_timer(WARMUP_TIME).timeout

	# Connect a per-frame sampler. SceneTree.process_frame fires after each
	# frame's _process pass; this is the right hook for frame-time data.
	process_frame.connect(_sample_frame)
	_sampling = true
	_start_time = Time.get_ticks_msec() / 1000.0

	await create_timer(_duration).timeout

	_sampling = false
	process_frame.disconnect(_sample_frame)

	var summary := _summarize()
	print("PERF_JSON: %s" % JSON.stringify(summary))
	inst.queue_free()
	quit(0)


func _build_scenario(name: String) -> Node:
	match name:
		"idle", "first_wave":
			return await _instance_scene(MAIN_SCENE)
		"bullet_stress":
			var inst := await _instance_scene(MAIN_SCENE)
			if inst == null:
				return null
			await create_timer(SETTLE_TIME).timeout
			_force_spawn_bullets(inst, STRESS_BULLET_COUNT)
			return inst
		"boss":
			# No quick fast-forward path today; treat as main + long settle.
			var i := await _instance_scene(MAIN_SCENE)
			if i == null:
				return null
			await create_timer(1.0).timeout
			return i
		_:
			return await _instance_scene(MAIN_SCENE)


func _instance_scene(path: String) -> Node:
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	if inst == null:
		return null
	root.add_child(inst)
	await create_timer(SETTLE_TIME).timeout
	return inst


func _force_spawn_bullets(_main: Node, n: int) -> void:
	var ps: PackedScene = load(BULLET_SCENE)
	if ps == null:
		return
	for i in n:
		var b: Node = ps.instantiate()
		if b == null:
			continue
		root.add_child(b)
		if b is Node2D:
			(b as Node2D).position = Vector2(20 + (i % 16) * 18, 50 + (i / 16) * 18)


func _sample_frame() -> void:
	if not _sampling:
		return
	var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 \
		+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_frame_ms.append(ms)
	_node_counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_resource_counts.append(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
	_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	if mem > _peak_mem:
		_peak_mem = mem


func _summarize() -> Dictionary:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var node_delta_per_sec := 0.0
	if _node_counts.size() >= 2 and _duration > 0.0:
		node_delta_per_sec = float(_node_counts[-1] - _node_counts[0]) / _duration
	return {
		"scenario": _scenario,
		"duration": _duration,
		"samples": _frame_ms.size(),
		"warmup_seconds": WARMUP_TIME,
		"headless_no_render": _draw_calls.size() > 0 and _max_int(_draw_calls) == 0,
		"frame_ms_p50": _percentile(sorted, 0.50),
		"frame_ms_p95": _percentile(sorted, 0.95),
		"frame_ms_max": (sorted[-1] if sorted.size() > 0 else 0.0),
		"node_peak": _max_int(_node_counts),
		"node_delta_per_sec": node_delta_per_sec,
		"resource_peak": _max_int(_resource_counts),
		"draw_calls_peak": _max_int(_draw_calls),
		"primitives_peak": _max_int(_primitives),
		"memory_mb_peak": _peak_mem,
	}


func _percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := int(floor(p * (sorted.size() - 1)))
	return sorted[idx]


func _max_int(arr: Array) -> int:
	var m := 0
	for v in arr:
		if int(v) > m:
			m = int(v)
	return m
