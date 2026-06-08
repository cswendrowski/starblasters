extends SceneTree

# Pattern cull/rework sanity (Roman 2026-06-08): every live movement key builds a valid
# pattern (incl. the new dive_return + the merged advance_retreat -> slow_advance), and the
# culled keys (s_curve / drifter_straight) fall through to the StraightDown default rather
# than erroring. Run: godot --headless --script res://tools/test_movement_keys.gd

const RESULT := "res://tools/_movement_keys_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")

func _init() -> void:
	var lines: Array = []
	var fails := 0
	var live := ["slow_advance", "advance_retreat", "top_dive", "dive_return", "lane_drift",
		"lane_weave", "lane_shift", "loiter", "beeline", "omni", "fast_straight", "side_traverse"]
	for k in live:
		var m = Roster.make_movement({"movement": k})
		if m == null or m.get_script() == null:
			lines.append("FAIL null pattern for '%s'" % k); fails += 1
		else:
			lines.append("OK %s -> %s" % [k, String(m.get_script().resource_path).get_file()])
	# Both collapsed keys must yield the same pattern (slow_advance look).
	var sa = Roster.make_movement({"movement": "slow_advance"})
	var ar = Roster.make_movement({"movement": "advance_retreat"})
	if sa.get_script() != ar.get_script():
		lines.append("FAIL advance_retreat not collapsed onto slow_advance"); fails += 1
	# Culled keys → StraightDown default, no crash.
	for k in ["s_curve", "drifter_straight"]:
		var m = Roster.make_movement({"movement": k})
		var nm := String(m.get_script().resource_path).get_file() if m and m.get_script() else "null"
		lines.append("culled '%s' -> %s" % [k, nm])
		if nm != "straight_down.gd":
			lines.append("FAIL culled '%s' did not fall to StraightDown" % k); fails += 1
	lines.append("MOVEMENT KEYS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
