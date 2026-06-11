extends SceneTree

# Wave-restructure test (Roman 2026-06-10): combat levels are 5 waves, each = 3 sub-wave FORMATION
# phrases (start/middle/end) + a BREATHER between waves. Verifies the score the conductor performs.
# Run: godot --headless --path . --script res://tools/test_wave_structure.gd

const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const Phrase = preload("res://scripts/levels/phrase.gd")
const RESULT := "res://tools/_wave_structure_result.txt"

func _init() -> void:
	var lines: Array = []
	var fails := 0
	# Test a couple of (sector, level) coords.
	for coord in [[1, 0], [2, 1], [3, 2]]:
		var sd: int = coord[0]
		var li: int = coord[1]
		var score = WaveGen.build_score(sd, li, false, -1)
		var nwaves: int = score.waves.size()
		lines.append("S%d L%d: %d waves (expect 5)" % [sd, li, nwaves])
		if nwaves != 5:
			lines.append("FAIL wave count != 5"); fails += 1
		var total_forms := 0
		for wi in nwaves:
			var w = score.waves[wi]
			var forms := 0
			var breathers := 0
			for ph in w.phrases:
				if ph.kind == Phrase.Kind.FORMATION:
					forms += 1
				elif ph.kind == Phrase.Kind.BREATHER:
					breathers += 1
			total_forms += forms
			# Each wave must have exactly 3 sub-wave formations.
			if forms != 3:
				lines.append("  FAIL wave %d has %d formations (expect 3)" % [wi, forms]); fails += 1
			# Waves 0..3 close with a breather; the final wave has none.
			var expect_breather: int = (1 if wi < nwaves - 1 else 0)
			if breathers != expect_breather:
				lines.append("  FAIL wave %d has %d breathers (expect %d)" % [wi, breathers, expect_breather]); fails += 1
		if total_forms != 15:
			lines.append("  FAIL total formations %d (expect 15)" % total_forms); fails += 1
		# The flat artifact (for warmup / extra-waves) is 15 specs too.
		var lvl = WaveGen.build(sd, li, false, -1)
		var nspecs: int = lvl.waves.size()
		if nspecs != 15:
			lines.append("  FAIL flat specs %d (expect 15)" % nspecs); fails += 1
	lines.append("WAVE STRUCTURE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
