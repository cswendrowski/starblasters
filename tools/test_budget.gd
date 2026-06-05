extends SceneTree

# M5 budget instrumentation: build real combat levels across a few (sector_depth,
# level_index) coordinates and report total enemy count vs the budget, so we can
# see/tune the volume curve. Also a sanity gate: totals should be well above the
# old ~18-48 range and land near the budget.
# Run: godot --headless --script res://tools/test_budget.gd

const RESULT := "res://tools/_budget_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0
	var coords := [[1, 0], [1, 4], [3, 2], [5, 6]]
	for c in coords:
		var lvl = WG.build(c[0], c[1], false)
		var total: int = 0
		for w in lvl.waves:
			total += int(w.count)
		var budget: int = WG._level_budget(c[0], c[1])
		lines.append("sd=%d li=%d  total=%d  budget=%d  waves(specs)=%d" % [c[0], c[1], total, budget, lvl.waves.size()])
		if total < 80:
			lines.append("  FAIL total under 80 - budget not driving volume"); fails += 1
		if total > int(budget * 1.5):
			lines.append("  FAIL total >1.5x budget - over-scaling"); fails += 1
	lines.append("BUDGET TEST: " + ("PASS" if fails == 0 else "FAIL"))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
