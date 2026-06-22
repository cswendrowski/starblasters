extends SceneTree

# Pattern set sanity (Roman 2026-06-08 overhaul): every live movement key builds a valid pattern,
# and removed/culled keys fall through to the StraightDown default rather than erroring.
# (make_movement({"movement": k}) with no scene -> resolve() falls back to the key directly.)
# Run: godot --headless --script res://tools/test_movement_keys.gd

const RESULT := "res://tools/_movement_keys_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")

func _init() -> void:
	var lines: Array = []
	var fails := 0
	var live := [
		"straight_crawl", "straight_slow", "straight_medium", "straight_fast", "straight_reflex",
		"straight_charge", "skirmish_loop", "skirmish_figure8", "drift_low", "drift_mid", "drift_high",
		"loiter_low", "loiter_mid", "loiter_high", "lane_weave", "lane_drift", "lane_shift",
		"lane_hook", "lane_cut", "side_turn", "side_dive", "side_traverse",
		"hunt_beeline", "hunt_omni", "skirmish_pendulum", "proximity_chase", "loiter_sweep",
	]
	for k in live:
		var m = Roster.make_movement({"movement": k})
		if m == null or m.get_script() == null:
			lines.append("FAIL null pattern for '%s'" % k); fails += 1
		else:
			lines.append("OK %s -> %s" % [k, String(m.get_script().resource_path).get_file()])
	# Removed / culled keys must fall to the StraightDown default (no crash).
	var dead := ["s_curve", "drifter_straight", "jet_charger", "side_cut", "slow_advance",
		"advance_retreat", "omni", "beeline", "bulwark_drift", "fast_straight", "firecore_straight",
		"dive_return", "lane_charge", "top_dive"]   # NB: "loiter"/"straight" are LIVE shape keys, not dead
	for k in dead:
		var m = Roster.make_movement({"movement": k})
		var nm := String(m.get_script().resource_path).get_file() if m and m.get_script() else "null"
		if nm != "straight_down.gd":
			lines.append("FAIL removed '%s' did not fall to StraightDown (-> %s)" % [k, nm]); fails += 1
	lines.append("MOVEMENT KEYS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
