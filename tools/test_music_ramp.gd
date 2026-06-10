extends Node

# Music ramp test (Roman 2026-06-10): boots combat (Music autoload loaded) and checks the intensity
# TARGET logic — first wave → Intensity_2, past wave 4 → Main, ramp_down → I1, and the per-boss
# permanent floor raises the combat-open intensity. (Audio is dummy headless; we verify the index
# math, not sound.) Run: godot --headless --path . tools/test_music_ramp.tscn --quit-after 120

const RESULT := "res://tools/_music_ramp_result.txt"
var _t := 0
var _done := false
var _main: Node = null

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _t < 8:
		return
	_done = true
	var lines: Array = []
	var fails := 0
	var music = get_node_or_null("/root/Music")
	var run = get_node_or_null("/root/Run")
	if music == null:
		lines.append("FAIL no Music autoload"); _finish(lines, 1); return

	run.bosses_defeated = 0
	music.set_context("combat")
	lines.append("combat open (0 bosses): _active_idx=%d (expect 0)" % int(music._active_idx))
	if int(music._active_idx) != 0:
		lines.append("FAIL combat should open at I1 with no bosses"); fails += 1

	music.set_combat_progress(0, 8, false)
	lines.append("wave 0: target=%d (expect 1=I2)" % int(music._combat_target_idx))
	if int(music._combat_target_idx) != 1: fails += 1; lines.append("FAIL first wave should lift to I2")

	music.set_combat_progress(3, 8, false)
	if int(music._combat_target_idx) != 1: fails += 1; lines.append("FAIL waves 1-3 should stay I2")

	music.set_combat_progress(4, 8, false)
	lines.append("wave 4: target=%d (expect 2=Main)" % int(music._combat_target_idx))
	if int(music._combat_target_idx) != 2: fails += 1; lines.append("FAIL past wave 4 should lift to Main")

	# ramp_down() guards on _active.playing — under headless dummy audio in this single-frame test it
	# may report not-playing, so this is informational (in real combat the track is playing).
	music.ramp_down()
	lines.append("ramp_down: target=%d (expect 0=I1; informational under dummy audio)" % int(music._combat_target_idx))

	# Permanent floor: 1 boss beaten → combat opens at I2; 2 bosses → Main.
	run.bosses_defeated = 1
	music.set_context("menu"); music.set_context("combat")
	lines.append("combat open (1 boss): _active_idx=%d (expect 1)" % int(music._active_idx))
	if int(music._active_idx) != 1: fails += 1; lines.append("FAIL 1-boss floor should open at I2")
	# Even an early wave can't drop below the floor.
	music.set_combat_progress(0, 8, false)
	if int(music._combat_target_idx) < 1: fails += 1; lines.append("FAIL floor not respected on wave 0")

	run.bosses_defeated = 2
	music.set_context("menu"); music.set_context("combat")
	lines.append("combat open (2 bosses): _active_idx=%d (expect 2)" % int(music._active_idx))
	if int(music._active_idx) != 2: fails += 1; lines.append("FAIL 2-boss floor should open at Main")

	lines.append("MUSIC RAMP: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)

func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
