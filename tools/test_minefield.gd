extends SceneTree

# Minefield producer (2026-06-09): build_minefield_score builds a non-empty score with the
# new variant mix (2 random non-basic types + an Armored sprinkle) on a basic field. Run:
# godot --headless --script res://tools/test_minefield.gd

const Levels = preload("res://scripts/levels/levels_v2.gd")
const RESULT := "res://tools/_minefield_result.txt"

func _init() -> void:
	var lines: Array = []
	var fails := 0
	# Run a handful of fields (RNG-seeded) so the variant-shuffle path is exercised.
	for n in range(8):
		var score = Levels.build_minefield_score()
		if score == null or score.waves.is_empty():
			lines.append("FAIL null/empty score"); fails += 1; break
		var w = score.waves[0]
		if w.phrases.is_empty():
			lines.append("FAIL no phrases"); fails += 1; break
	if fails == 0:
		var s = Levels.build_minefield_score()
		lines.append("minefield OK — %d phrases (banner=%s)" % [s.waves[0].phrases.size(), s.waves[0].banner])
	lines.append("MINEFIELD: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	print("\n".join(PackedStringArray(lines)))
	quit(1 if fails > 0 else 0)
