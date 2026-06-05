extends SceneTree

# Mine + asteroid hazards converted to phrase-native CombatScores (lane-shaped
# drops + breathers). Verifies the scores are well-formed: FORMATION phrases with
# valid specs + real lane shapes (wall/pincer/top_spread), and BREATHERs with
# alive_floor == -1 (a >=0 floor would insta-skip on a pure-hazard level where the
# combatant count is always 0). Run:
#   godot --headless --script res://tools/test_hazard_score.gd

const RESULT := "res://tools/_hazard_score_result.txt"
const LV := preload("res://scripts/levels/levels_v2.gd")
const CombatScore := preload("res://scripts/levels/combat_score.gd")
const Phrase := preload("res://scripts/levels/phrase.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0
	var builders := {
		"minefield": LV.build_minefield_score(),
		"asteroid": LV.build_asteroid_field_score(),
	}
	for name in builders:
		var score = builders[name]
		if not (score is CombatScore) or score.waves.is_empty():
			lines.append("FAIL %s: not a CombatScore / empty" % name); fails += 1; continue
		var w = score.waves[0]
		var n_form: int = 0
		var n_breath: int = 0
		var shapes: Dictionary = {}
		for ph in w.phrases:
			if ph.kind == Phrase.Kind.FORMATION:
				n_form += 1
				shapes[str(ph.shape)] = true
				if ph.specs.is_empty() or ph.specs[0] == null or ph.specs[0].enemy_scene == null:
					lines.append("FAIL %s: formation has invalid spec" % name); fails += 1
			elif ph.kind == Phrase.Kind.BREATHER:
				n_breath += 1
				if ph.alive_floor != -1:
					lines.append("FAIL %s: breather alive_floor=%d (would insta-skip)" % [name, ph.alive_floor]); fails += 1
		if n_form < 3:
			lines.append("FAIL %s: only %d formations" % [name, n_form]); fails += 1
		if n_breath < 1:
			lines.append("FAIL %s: no breathers" % name); fails += 1
		lines.append("%s: formations=%d breathers=%d shapes=%s banner='%s'" % [
			name, n_form, n_breath, str(shapes.keys()), w.banner])
	lines.append("HAZARD SCORE TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
