class_name CombatSlice
extends RefCounted

# Hand-authored showcase CombatScore demonstrating the full composed model end to
# end: shaped FORMATIONS (wall, pincer) sent as bursts + FILLER trickle bridging
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

const DART := "res://scenes/enemies/enemy_dart.tscn"
const DRIFTER := "res://scenes/enemies/enemy_drifter.tscn"

# lane_path.gd Shape enum order: 0 = STRAIGHT, 1 = WEAVE, 2 = HOOK.
const LP_STRAIGHT := 0
const LP_WEAVE := 1


static func _lane_path(shape_int: int, down: float = 120.0) -> Resource:
	var LanePath := load("res://scripts/enemies/patterns/lane_path.gd")
	var lp = LanePath.new()
	lp.shape = shape_int
	lp.down_speed = down
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
	# Wave 1 — a WALL of drifters (one safe gap to thread), darts trickling, exhale.
	score.waves.append(_wave("WALL", [
		_formation(&"wall", [_spec(DRIFTER, 6, 0.2, _lane_path(LP_STRAIGHT))]),
		_filler([_spec(DART, 1)], 2.0, 6),
		_breather(1.5),
	]))
	# Wave 2 — a PINCER of darts converging from the edges, filler, exhale.
	score.waves.append(_wave("PINCER", [
		_formation(&"pincer", [_spec(DART, 6, 0.2, _lane_path(LP_STRAIGHT))]),
		_filler([_spec(DART, 1)], 2.5, 8),
		_breather(1.5),
	]))
	# Wave 3 — a spread SWEEP finale of weaving drifters (alternate-anchor lanes).
	score.waves.append(_wave("SWEEP", [
		_formation(&"spread", [_spec(DRIFTER, 10, 0.15, _lane_path(LP_WEAVE))]),
	]))
	return score
