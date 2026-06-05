extends SceneTree

# M5 native emission: WaveGen.build_score() emits a CombatScore directly (the score
# the conductor performs via start_score), equivalent to lifting build()'s LevelData
# through the shared builder. Verifies the score is well-formed + matches the flat path.
# Run: godot --headless --script res://tools/test_build_score.gd

const RESULT := "res://tools/_build_score_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")
const ScoreAdapter := preload("res://scripts/levels/score_adapter.gd")
const CombatScore := preload("res://scripts/levels/combat_score.gd")
const Phrase := preload("res://scripts/levels/phrase.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0
	var run = root.get_node_or_null("Run")
	if run != null:
		run.run_seed = 31337

	# build_score returns a real, non-empty CombatScore.
	var score = WG.build_score(1, 1, false)
	if not (score is CombatScore):
		lines.append("FAIL build_score did not return a CombatScore"); fails += 1
	elif score.waves.is_empty():
		lines.append("FAIL build_score produced no waves"); fails += 1
	else:
		# Each ScoreWave has phrases; the first dispatched phrase is a spawnable FORMATION.
		var p0 = score.waves[0].phrases[0]
		if p0.kind != Phrase.Kind.FORMATION or p0.specs.is_empty() or p0.specs[0] == null or p0.specs[0].enemy_scene == null:
			lines.append("FAIL first phrase not a spawnable FORMATION"); fails += 1

	# Equivalence with the flat path (same seed -> same content).
	var native = WG.build_score(1, 1, false)
	var lifted = ScoreAdapter.from_level_data(WG.build(1, 1, false))
	if native.waves.size() != lifted.waves.size():
		lines.append("FAIL native waves=%d != lifted waves=%d" % [native.waves.size(), lifted.waves.size()]); fails += 1

	# Boss score builds too.
	var boss = WG.build_score(1, 0, true)
	if not (boss is CombatScore) or boss.waves.is_empty():
		lines.append("FAIL boss build_score empty/invalid"); fails += 1

	lines.append("build_score(1,1) waves=%d ; boss waves=%d ; equiv=%s" % [
		score.waves.size(), boss.waves.size(), str(native.waves.size() == lifted.waves.size())])
	lines.append("BUILD SCORE TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	return true
