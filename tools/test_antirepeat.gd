extends SceneTree

# M5 anti-repetition: _pick_entry(..., avoid_movement) must not return an entry
# whose movement archetype matches avoid_movement when alternatives exist. At
# sector 1 node 1 the common pool is dart/bomb_drone (fast_straight) + drifter
# (drifter_straight), so avoiding "fast_straight" should always pick the drifter.
# Run: godot --headless --script res://tools/test_antirepeat.gd

const RESULT := "res://tools/_antirepeat_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	# With avoid, fast_straight should never come back (drifter is available).
	var leaked: int = 0
	for _i in 80:
		var e = WG._pick_entry(rng, 1, 0, [], PackedStringArray(), 2, "fast_straight")  # 2 = Tier.RARE (no cap)
		if str(e.get("movement", "")) == "fast_straight":
			leaked += 1
	if leaked > 0:
		lines.append("FAIL avoid leaked fast_straight %d/80" % leaked); fails += 1

	# Control: without avoid, fast_straight DOES appear (proves it's in the pool,
	# so the filter is doing real work).
	var seen: int = 0
	for _i in 80:
		var e2 = WG._pick_entry(rng, 1, 0, [])
		if str(e2.get("movement", "")) == "fast_straight":
			seen += 1
	if seen == 0:
		lines.append("FAIL control: fast_straight never appeared without avoid"); fails += 1

	lines.append("antirepeat: avoid_leaked=%d  control_seen=%d/80" % [leaked, seen])
	lines.append("ANTIREPEAT TEST: " + ("PASS" if fails == 0 else "FAIL"))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
