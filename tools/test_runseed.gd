extends SceneTree

# Verifies run-seed folding (wave spec §7.2): the SAME node is reproducible within
# a run (same run_seed -> identical comp) but varies across runs (different
# run_seed -> different comp). Autoloads aren't mounted in --script runs, so we
# inject a stub "Run" node with a run_seed.
# Run: godot --headless --script res://tools/test_runseed.gd

const RESULT := "res://tools/_runseed_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")

var _done := false


func _sig(level) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for w in level.waves:
		var scene: String = (w.enemy_scene.resource_path if w.enemy_scene else "?")
		parts.append("%s|%d|%d" % [scene.get_file(), int(w.count), int(w.formation)])
	return "/".join(parts)


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	# The real Run autoload is present by the first _process frame; set its seed.
	var run = root.get_node_or_null("Run")
	if run == null:
		lines.append("FAIL Run autoload not present")
		var ff := FileAccess.open(RESULT, FileAccess.WRITE)
		if ff != null:
			ff.store_string("\n".join(PackedStringArray(lines)))
			ff.close()
		return true

	run.run_seed = 111
	var rs1: int = WG._run_seed()
	var sd1: int = WG._stable_seed(1, 0, false)
	var a1: String = _sig(WG.build(1, 0, false))
	run.run_seed = 111
	var a2: String = _sig(WG.build(1, 0, false))
	run.run_seed = 222
	var rs2: int = WG._run_seed()
	var sd2: int = WG._stable_seed(1, 0, false)
	var b: String = _sig(WG.build(1, 0, false))
	lines.append("diag: rs1=%d sd1=%d  rs2=%d sd2=%d" % [rs1, sd1, rs2, sd2])

	if a1 != a2:
		lines.append("FAIL same run_seed not reproducible"); fails += 1
	if a1 == b:
		lines.append("FAIL different run_seed produced identical comp"); fails += 1
	lines.append("seed111: %s" % a1)
	lines.append("seed222: %s" % b)
	lines.append("RUNSEED TEST: " + ("PASS" if fails == 0 else "FAIL"))

	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	return true
