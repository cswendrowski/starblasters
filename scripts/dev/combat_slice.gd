class_name CombatSlice
extends RefCounted

# Hand-authored showcase CombatScore demonstrating the full composed model end to
# end: shaped FORMATIONS (wall, pincer, step_wall) sent as bursts + FILLER trickle bridging
# + BREATHER beats + lane placement + the streaming concurrency cap.
#
# Formation enemies get an explicit lane_path movement override (STRAIGHT/WEAVE)
# so they descend cleanly anchored to their spawn lane — this both guarantees
# motion (some chassis park without wave context / are bespoke) and is the first
# place lane_path drives real play. Only enemy_core chassis are used so the
# movement override actually applies.
#
# Launched from the dev menu ("Combat Slice"), which sets Run meta "combat_slice";
# main.gd routes it through WaveDirector.start_score. A vertical slice to FEEL the
# design before the producer-side WaveGen v2. See
# docs/combat_construction_plan_2026-06-03.md.

const DART := "res://scenes/enemies/core/enemy_core_s_dart.tscn"

# lane_path.gd Shape enum order: 0 = STRAIGHT, 1 = WEAVE, 2 = HOOK, 3 = STEP.
const LP_STRAIGHT := 0
const LP_WEAVE := 1
const LP_STEP := 3


static func _lane_path(shape_int: int, down: float = 120.0, weave_lanes: float = 1.0) -> Resource:
	var LanePath := load("res://scripts/enemies/patterns/lane_path.gd")
	var lp = LanePath.new()
	lp.shape = shape_int
	lp.weave_lanes = weave_lanes
	return lp


static func _step_path(down: float = 70.0, hold: float = 1.0, step_t: float = 0.3, lanes: int = 1, pingpong: bool = true) -> Resource:
	var LanePath := load("res://scripts/enemies/patterns/lane_path.gd")
	var lp = LanePath.new()
	lp.shape = LP_STEP
	lp.hold_time = hold
	lp.step_time = step_t
	lp.step_lanes = lanes
	lp.step_pingpong = pingpong
	return lp


static func _spec(scene_path: String, count: int, interval: float = 0.2, move: Resource = null) -> Resource:
	var WaveDef := load("res://scripts/levels/wave_def.gd")
	var sp = WaveDef.new()
	sp.enemy_scene = load(scene_path)
	sp.count = count
	sp.spawn_interval = interval
	sp.formation = 0
	if move != null:
		sp.movement_override = move
	return sp


static func _formation(shape: StringName, specs: Array) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.shape = shape
	for s in specs:
		ph.specs.append(s)
	return ph


static func _filler(pool: Array, rate: float, budget: int) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FILLER
	for s in pool:
		ph.pool.append(s)
	ph.rate = rate
	ph.until = &"budget"
	ph.until_value = float(budget)
	return ph


static func _breather(duration: float) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.BREATHER
	ph.duration = duration
	return ph


static func _wave(banner: String, phrases: Array) -> ScoreWave:
	var w := ScoreWave.new()
	w.banner = banner
	for p in phrases:
		w.phrases.append(p)
	return w


static func build() -> CombatScore:
	var score := CombatScore.new()
	score.level_name = "Combat Slice"
	# Slow drifter chaff for filler — descends BELOW formation speed (90 < 120) so
	# it trails the formation instead of overtaking it (playtest fix). Darts are
	# reaction-testers, reserved for the pincer formation, not chaff.
	# Each wave: FORMATION -> short breather (formation clears the entry band) ->
	# FILLER bridge -> longer exhale before the next wave.
	# Wave 1 — a WALL of drifters (one safe gap to thread).
	score.waves.append(_wave("WALL", [
		_formation(&"wall", [_spec(DART, 6, 0.2, _lane_path(LP_STRAIGHT, 120.0))]),
		_breather(0.7),
		_filler([_spec(DART, 1, 0.2, _lane_path(LP_STRAIGHT, 90.0))], 1.5, 6),
		_breather(1.2),
	]))
	# Wave 2 — a PINCER of darts converging from the edges (deliberate pressure).
	score.waves.append(_wave("PINCER", [
		_formation(&"pincer", [_spec(DART, 6, 0.2, _lane_path(LP_STRAIGHT, 120.0))]),
		_breather(0.7),
		_filler([_spec(DART, 1, 0.2, _lane_path(LP_STRAIGHT, 90.0))], 1.5, 8),
		_breather(1.2),
	]))
	# Wave 3 — SWEEP: the original gentle weave (visual busyness / distraction).
	score.waves.append(_wave("SWEEP", [
		_formation(&"spread", [_spec(DART, 10, 0.2, _lane_path(LP_WEAVE, 120.0, 1.0))]),
	]))
	# Wave 4 — STEP: slow hold-then-hop drifters (ping-pong between adjacent lanes)
	# that force you to commit to a lane and re-read as they camp + relocate.
	score.waves.append(_wave("STEP", [
		_formation(&"spread", [_spec(DART, 8, 0.25, _step_path(70.0, 1.0, 0.3, 1, true))]),
	]))
	# Wave 5 — STEP WALL: a contiguous row fills all but one lane, spawned in ONE frame, then
	# shifts the gap in UNISON (synced step). The step_wall dispatch lays out the lanes + stamps
	# the shared sync params, and the director forces Shape.STEP onto the lane_path override — so
	# this is the live demo of the production step-wall (vs Wave 4's per-instance hop). The
	# movement override just needs to be a lane_path so the dispatch's step stamp applies.
	score.waves.append(_wave("STEP WALL", [
		_formation(&"step_wall", [_spec(DART, 6, 0.2, _lane_path(LP_STRAIGHT, 90.0))]),
		_breather(1.5),
	]))
	return score
