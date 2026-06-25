extends Node

# Music intensity schema test (rewritten 2026-06-24 for the Ovani migration).
# Verifies the dynamic combat-intensity math on the `Music` autoload:
#   - deeper into a combat level (wave progress) → hotter
#   - more damaged → hotter
#   - deeper into the run (combats cleared) → hotter baseline
#   - ramp_down() decompresses to 0, a boss pins Main (1.0)
# Audio is dummy under headless; we check the intensity TARGET math, not sound.
# Run: godot --headless --path . tools/test_music_ramp.tscn --quit-after 120

const RESULT := "res://tools/_music_ramp_result.txt"
var _t := 0
var _done := false


func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _t < 4:
		return
	_done = true

	var lines: Array = []
	var fails := 0
	var music = get_node_or_null("/root/Music")
	var run = get_node_or_null("/root/Run")
	if music == null:
		_finish(["FAIL no Music autoload"], 1)
		return
	if run != null and run.has_method("new_run"):
		run.new_run()
	if run != null:
		run.combats_in_sector = 0
		run.sectors_cleared = 0

	music.set_context("combat")
	var i_open: float = music._intensity_target
	lines.append("combat open (shallow): intensity=%.3f" % i_open)

	music.set_combat_progress(0, 8, false)
	var i_w0: float = music._intensity_target

	music.set_combat_progress(7, 8, false)
	var i_w7: float = music._intensity_target
	lines.append("deep wave 7/8: intensity=%.3f (expect > wave0 %.3f)" % [i_w7, i_w0])
	if not (i_w7 > i_w0 + 0.2):
		fails += 1
		lines.append("FAIL wave progress should raise intensity")

	music.notify_damage(3, 0)   # fully damaged
	var i_dmg: float = music._intensity_target
	lines.append("fully damaged: intensity=%.3f (expect > deep wave)" % i_dmg)
	if not (i_dmg > i_w7):
		fails += 1
		lines.append("FAIL damage should raise intensity")

	# Deeper run → hotter combat open.
	if run != null:
		run.combats_in_sector = 6
	music.set_context("menu")
	music.set_context("combat")
	var i_deep: float = music._intensity_target
	lines.append("combat open (deep run): intensity=%.3f (expect > shallow %.3f)" % [i_deep, i_open])
	if not (i_deep > i_open):
		fails += 1
		lines.append("FAIL run progress should raise open intensity")

	music.ramp_down()
	lines.append("ramp_down: intensity=%.3f (expect 0)" % music._intensity_target)
	if music._intensity_target > 0.001:
		fails += 1
		lines.append("FAIL ramp_down should reach 0")

	music.set_context("boss")
	lines.append("boss: intensity=%.3f (expect 1.0)" % music._intensity_target)
	if absf(music._intensity_target - 1.0) > 0.001:
		fails += 1
		lines.append("FAIL boss should pin Main")

	lines.append("MUSIC SCHEMA: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)


func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
