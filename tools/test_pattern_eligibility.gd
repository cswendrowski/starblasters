extends SceneTree

# Pattern eligibility plumbing (pattern_eligibility_2026-06-08.md). resolve() is MATRIX-AUTHORITATIVE:
# non-vary returns the scene's identity (so the tool controls assignment); vary returns a flat-random
# ELIGIBLE key; unmapped scenes fall back to the entry's own movement.
# Run: godot --headless --script res://tools/test_pattern_eligibility.gd

const RESULT := "res://tools/_pe_result.txt"
const PE := preload("res://scripts/levels/pattern_eligibility.gd")
const PUSH := "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn"
const INTERCEPTOR := "res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn"

func _init() -> void:
	var lines: Array = []
	var fails := 0
	# Non-vary: the MATRIX identity drives, regardless of the entry's own movement.
	var k1: String = PE.resolve({"scene": PUSH, "movement": "whatever"})
	if k1 != PE.identity_for(PUSH):
		lines.append("FAIL non-vary '%s' != identity '%s'" % [k1, PE.identity_for(PUSH)]); fails += 1
	# Vary: always one of the push's eligible keys.
	var elig: Array = PE.eligible_for(PUSH)
	var vary_ok := true
	for _i in range(30):
		var kv: String = PE.resolve({"scene": PUSH, "movement": "whatever", "vary": true})
		if not (kv in elig):
			vary_ok = false; break
	if not vary_ok:
		lines.append("FAIL vary returned a non-eligible key"); fails += 1
	# identity_for (interceptor: top_dive -> side_dive 2026-06-08 -> side_turn 2026-06-22 collapse)
	if PE.identity_for(INTERCEPTOR) != "side_turn":
		lines.append("FAIL interceptor identity != side_turn"); fails += 1
	# Unmapped scene -> falls back to the entry movement.
	if PE.resolve({"scene": "res://nope.tscn", "movement": "straight_medium"}) != "straight_medium":
		lines.append("FAIL unmapped did not fall back to entry movement"); fails += 1
	lines.append("identity(push)=%s eligible(push)=%s" % [PE.identity_for(PUSH), str(elig)])
	lines.append("PATTERN ELIGIBILITY: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
