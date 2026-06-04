extends SceneTree

# Headless unit check for score_adapter.gd (M3/M4). Builds a flat LevelData with
# an announced wave + two silent sub-waves + another announced wave, lifts it to
# a CombatScore, and verifies: silent-grouping into 2 ScoreWaves, phrase counts,
# banners, faithful spec carry-through, and Formation->shape/entry mapping.
# Run: godot --headless --script res://tools/test_score_adapter.gd

const RESULT := "res://tools/_score_adapter_result.txt"
const WaveDef := preload("res://scripts/levels/wave_def.gd")
const LevelDef := preload("res://scripts/levels/level_def.gd")

var _log: Array = []


func _say(s: String) -> void:
	_log.append(s)


func _init() -> void:
	var fails := 0

	var lvl = LevelDef.new()
	lvl.level_name = "Test"
	var a = WaveDef.new()
	a.announce_text = "WAVE A"; a.silent = false; a.count = 5; a.formation = 0
	var s1 = WaveDef.new()
	s1.silent = true; s1.count = 3; s1.formation = 1
	var s2 = WaveDef.new()
	s2.silent = true; s2.count = 3; s2.formation = 4
	var b = WaveDef.new()
	b.announce_text = "WAVE B"; b.silent = false; b.count = 4; b.formation = 2
	lvl.waves = [a, s1, s2, b]

	var score = ScoreAdapter.from_level_data(lvl)

	if score.level_name != "Test":
		_say("FAIL level_name=%s" % score.level_name); fails += 1
	if score.waves.size() != 2:
		_say("FAIL wave count=%d expected 2" % score.waves.size()); fails += 1
	else:
		if score.waves[0].phrases.size() != 3:
			_say("FAIL w0 phrases=%d expected 3" % score.waves[0].phrases.size()); fails += 1
		if score.waves[1].phrases.size() != 1:
			_say("FAIL w1 phrases=%d expected 1" % score.waves[1].phrases.size()); fails += 1
		if score.waves[0].banner != "WAVE A":
			_say("FAIL w0 banner=%s" % score.waves[0].banner); fails += 1
		if score.waves[1].banner != "WAVE B":
			_say("FAIL w1 banner=%s" % score.waves[1].banner); fails += 1
		var ph = score.waves[0].phrases[0]
		if ph.kind != Phrase.Kind.FORMATION:
			_say("FAIL phrase kind=%d" % ph.kind); fails += 1
		if ph.specs.size() != 1 or ph.specs[0] != a:
			_say("FAIL spec not carried faithfully"); fails += 1
		if ph.shape != &"left_to_right":
			_say("FAIL w0p0 shape=%s" % ph.shape); fails += 1
		if score.waves[0].phrases[2].entry != &"side":
			_say("FAIL s2 entry=%s expected side" % score.waves[0].phrases[2].entry); fails += 1

	if fails == 0:
		_say("SCORE_ADAPTER TEST: PASS")
	else:
		_say("SCORE_ADAPTER TEST: %d FAIL(s)" % fails)
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_log)))
		f.close()
	quit()
