extends SceneTree

# Pattern eligibility plumbing (pattern_eligibility_2026-06-08.md): resolve() returns the entry's
# own movement (identity) when vary is off — behavior-preserving — and a flat-random ELIGIBLE key
# when "vary": true; unmapped scenes fall back to the entry movement.
# Run: godot --headless --script res://tools/test_pattern_eligibility.gd

const RESULT := "res://tools/_pe_result.txt"
const PE := preload("res://scripts/levels/pattern_eligibility.gd")
const PUSH := "res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn"
const INTERCEPTOR := "res://scenes/enemies/factions/privateer/enemy_interceptor.tscn"

func _init() -> void:
	var lines: Array = []
	var fails := 0
	# Non-vary: identity (behavior-preserving) — returns the entry's own movement verbatim.
	var k1: String = PE.resolve({"scene": PUSH, "movement": "slow_advance"})
	if k1 != "slow_advance":
		lines.append("FAIL non-vary returned '%s' != slow_advance" % k1); fails += 1
	# Vary: always one of the push's eligible keys.
	var elig: Array = PE.eligible_for(PUSH)
	var vary_ok := true
	for _i in range(30):
		var kv: String = PE.resolve({"scene": PUSH, "movement": "slow_advance", "vary": true})
		if not (kv in elig):
			vary_ok = false; break
	if not vary_ok:
		lines.append("FAIL vary returned a non-eligible key"); fails += 1
	# identity_for
	if PE.identity_for(INTERCEPTOR) != "top_dive":
		lines.append("FAIL interceptor identity != top_dive"); fails += 1
	# Unmapped scene + vary → falls back to the entry movement.
	if PE.resolve({"scene": "res://nope.tscn", "movement": "straight", "vary": true}) != "straight":
		lines.append("FAIL unmapped vary did not fall back"); fails += 1
	lines.append("eligible(push)=%s" % str(elig))
	lines.append("PATTERN ELIGIBILITY: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
