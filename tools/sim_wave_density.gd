extends SceneTree

# Diagnose the "1-2 enemies on wide lanes at slow intervals" trickle: build real levels and dump each
# wave's type / tier / chaff / count / formation, flagging small-count spread waves. Temp diag.
#   godot --path . --headless -s tools/sim_wave_density.gd

const FORM := ["L→R", "R→L", "RAND", "CTR_OUT", "SIDE_ALT", "TANDEM", "WALL", "PINCER", "STEP"]
const TIER := ["COM", "UNC", "RARE"]

func _initialize() -> void:
	var WaveGen = load("res://scripts/levels/wave_generator.gd")
	var Roster = load("res://scripts/levels/enemy_roster.gd")
	for coord in [[1, 0], [1, 2], [2, 1]]:
		var sd: int = coord[0]
		var li: int = coord[1]
		var level = WaveGen.build(sd, li, false, -1)
		print("\n=== sector %d  node %d  (%d waves) ===" % [sd, li, level.waves.size()])
		var distinct := {}
		var trickle := 0
		for w in level.waves:
			if w == null or w.enemy_scene == null:
				continue
			var path: String = w.enemy_scene.resource_path
			distinct[path] = true
			var e: Dictionary = Roster.entry_for_scene(path)
			var nm: String = path.get_file().replace(".tscn", "")
			var tier: int = int(e.get("tier", 0))
			var chaff: bool = bool(e.get("chaff", false))
			var fm: int = int(w.formation)
			var shp: String = String(w.shape_override) if String(w.shape_override) != "" else FORM[fm] if fm < FORM.size() else "?"
			# A "trickle": small count, not a burst shape (sweep/center), slow interval.
			var is_burst: bool = fm >= 6 or String(w.shape_override) != "" or String(w.drift_mode) != "" or float(w.spawn_interval) < 0.2
			var flag: String = ""
			if int(w.count) <= 3 and not is_burst:
				flag = "  <-- TRICKLE"
				trickle += 1
			print("  %-26s %-4s chaff=%-5s count=%-3d int=%.2f  %-8s%s" % [
				nm, TIER[tier] if tier < 3 else "?", str(chaff), int(w.count), float(w.spawn_interval), shp, flag])
		print("  -> distinct unit types: %d   trickle waves: %d" % [distinct.size(), trickle])
	# BOSS run-up: count lead-in waves before the boss.
	var boss = WaveGen.build(2, 3, true, -1)
	var leadin := 0
	print("\n=== BOSS level (sector 2) — %d total waves ===" % boss.waves.size())
	for w in boss.waves:
		if w == null or w.enemy_scene == null:
			continue
		var nm: String = w.enemy_scene.resource_path.get_file().replace(".tscn", "")
		var is_boss_wave: bool = nm.begins_with("boss")
		if not is_boss_wave:
			leadin += 1
		print("  %-26s count=%-3d%s" % [nm, int(w.count), "   <== BOSS" if is_boss_wave else ""])
	print("  -> lead-in waves before boss: %d (want >= 5)" % leadin)
	quit()
