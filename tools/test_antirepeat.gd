extends SceneTree

# M5 anti-repetition: _pick_entry(..., avoid_movement) must not return an entry
# whose movement archetype matches avoid_movement when alternatives exist. The common
# pool has both "straight" descenders (dart, …) and non-straight movers (hunt_beeline /
# lane_* / …), so avoiding "straight" must always pick a non-straight one.
# Run: godot --headless --script res://tools/test_antirepeat.gd

const RESULT := "res://tools/_antirepeat_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	# With avoid, straight should never come back (drifter is available).
	var leaked: int = 0
	for _i in 80:
		var e = WG._pick_entry(rng, 1, 0, [], PackedStringArray(), 2, "straight")  # 2 = Tier.RARE (no cap)
		if str(e.get("movement", "")) == "straight":
			leaked += 1
	if leaked > 0:
		lines.append("FAIL avoid leaked straight %d/80" % leaked); fails += 1

	# Control: without avoid, straight DOES appear (proves it's in the pool,
	# so the filter is doing real work).
	var seen: int = 0
	for _i in 80:
		var e2 = WG._pick_entry(rng, 1, 0, [])
		if str(e2.get("movement", "")) == "straight":
			seen += 1
	if seen == 0:
		lines.append("FAIL control: straight never appeared without avoid"); fails += 1

	lines.append("antirepeat: avoid_leaked=%d  control_seen=%d/80" % [leaked, seen])
	lines.append("ANTIREPEAT TEST: " + ("PASS" if fails == 0 else "FAIL"))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
