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

	# Combat intensity is a live envelope (presence * ceiling + streak) driven in
	# _process; under this single-frame headless test with no enemies in-tree we
	# verify the CEILING math + the kill-streak meter, not the per-frame envelope.
	music.set_context("combat")
	var i_open: float = music._combat_ceiling()
	lines.append("combat ceiling (shallow): %.3f" % i_open)

	music.set_combat_progress(0, 8, false)
	var i_w0: float = music._combat_ceiling()

	music.set_combat_progress(7, 8, false)
	var i_w7: float = music._combat_ceiling()
	lines.append("deep wave 7/8 ceiling: %.3f (expect > wave0 %.3f)" % [i_w7, i_w0])
	if not (i_w7 > i_w0 + 0.2):
		fails += 1
		lines.append("FAIL wave progress should raise the ceiling")

	music.notify_damage(3, 0)   # fully damaged
	var i_dmg: float = music._combat_ceiling()
	lines.append("fully damaged ceiling: %.3f (expect > deep wave)" % i_dmg)
	if not (i_dmg > i_w7):
		fails += 1
		lines.append("FAIL damage should raise the ceiling")

	# Combat must OPEN QUIET — the live intensity starts at 0, not at the ceiling.
	lines.append("combat-open live intensity: %.3f (expect 0 — ramps up in _process)" % music._player.Intensity)
	if music._player.Intensity > 0.001:
		fails += 1
		lines.append("FAIL combat should open quiet (intensity 0)")

	# Kill-streak heat rises with kills and is capped.
	music.notify_kill(); music.notify_kill(); music.notify_kill()
	lines.append("streak heat after 3 kills: %.3f (expect > 0, <= 1)" % music._streak_heat)
	if music._streak_heat <= 0.0:
		fails += 1
		lines.append("FAIL kills should add streak heat")

	# Deeper run → hotter combat ceiling.
	if run != null:
		run.combats_in_sector = 6
	music.set_context("menu")
	music.set_context("combat")
	var i_deep: float = music._combat_ceiling()
	lines.append("combat ceiling (deep run): %.3f (expect > shallow %.3f)" % [i_deep, i_open])
	if not (i_deep > i_open):
		fails += 1
		lines.append("FAIL run progress should raise the ceiling")

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

	# Warm-up handoff: warm_up_combat arms warming + the combat context; the
	# following set_context("combat") must hand off to the live envelope (not
	# cold-open) — combat_active true, warming cleared.
	music.warm_up_combat(0.22, 3.0)
	var warmed: bool = music._warming and music._context == "combat"
	music.set_context("combat")
	lines.append("warm-up handoff: warmed=%s -> combat_active=%s warming=%s" % [
		str(warmed), str(music._combat_active), str(music._warming)])
	if not (warmed and music._combat_active and not music._warming):
		fails += 1
		lines.append("FAIL warm-up should hand off to live combat")

	# Regression: re-entering "silent" (e.g. returning to the dev menu) must stay
	# silenced, not un-silence a leftover track.
	music.set_context("menu")     # play something audible
	music.set_context("silent")   # dev menu silences
	music.set_context("silent")   # dev menu re-opened — must NOT bring music back
	lines.append("re-enter silent: _silenced=%s (expect true)" % str(music._silenced))
	if not music._silenced:
		fails += 1
		lines.append("FAIL re-entering silent should stay silenced")

	lines.append("MUSIC SCHEMA: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)


func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
