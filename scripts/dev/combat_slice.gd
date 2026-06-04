class_name CombatSlice
extends RefCounted

# Hand-authored showcase CombatScore demonstrating the full composed model end to
# end: shaped FORMATIONS (wall, pincer) sent as bursts + FILLER trickle bridging
# + BREATHER beats + lane placement + the streaming concurrency cap.
#
# Launched from the dev menu ("Combat Slice"), which sets Run meta "combat_slice";
# main.gd routes it through WaveDirector.start_score. This is a vertical slice to
# FEEL the design before the producer-side WaveGen v2 work. See
# docs/combat_construction_plan_2026-06-03.md.

const DART := "res://scenes/enemies/enemy_dart.tscn"
const DRIFTER := "res://scenes/enemies/enemy_drifter.tscn"
const INTERCEPTOR := "res://scenes/enemies/enemy_interceptor.tscn"


static func _spec(scene_path: String, count: int, interval: float = 0.2) -> Resource:
	var WaveDef := load("res://scripts/levels/wave_def.gd")
	var sp = WaveDef.new()
	sp.enemy_scene = load(scene_path)
	sp.count = count
	sp.spawn_interval = interval
	sp.formation = 0
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
	# Wave 1 — a WALL of drifters (pick a gap!), darts trickling between, exhale.
	score.waves.append(_wave("WALL", [
		_formation(&"wall", [_spec(DRIFTER, 6)]),
		_filler([_spec(DART, 1)], 2.0, 6),
		_breather(1.5),
	]))
	# Wave 2 — a PINCER of interceptors from the edges, mixed filler, exhale.
	score.waves.append(_wave("PINCER", [
		_formation(&"pincer", [_spec(INTERCEPTOR, 6)]),
		_filler([_spec(DART, 1), _spec(DRIFTER, 1)], 2.5, 8),
		_breather(1.5),
	]))
	# Wave 3 — a spread SWEEP finale (alternate-anchor stream).
	score.waves.append(_wave("SWEEP", [
		_formation(&"spread", [_spec(DART, 10, 0.15)]),
	]))
	return score
