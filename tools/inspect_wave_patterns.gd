extends SceneTree

# Inspect the wave-pattern editor's saved library (user://tuners/wave_patterns.json) and the
# exported snapshot, so the formations can be intaken into authored_patterns.DATA.

const SAVE_PATH := "user://tuners/wave_patterns.json"
const EXPORT_PATH := "user://tuners/wave_patterns_export.txt"

func _initialize() -> void:
	print("user:// = ", ProjectSettings.globalize_path("user://"))
	_report(SAVE_PATH)
	print("export.txt exists: ", FileAccess.file_exists(EXPORT_PATH))
	var ad := load("res://scripts/levels/authored_patterns.gd")
	var cur: Array = ad.get_script_constant_map().get("DATA", [])
	print("current authored_patterns.DATA count: ", cur.size())
	quit()

func _report(path: String) -> void:
	if not FileAccess.file_exists(path):
		print("MISSING: ", path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		print("NOT AN ARRAY: ", path)
		return
	print("=== %s : %d patterns ===" % [path.get_file(), (parsed as Array).size()])
	var idx := 0
	for p in parsed:
		if p is Dictionary:
			var nm: String = str(p.get("name", "?"))
			var pc: int = (p.get("placements", []) as Array).size()
			var lock = p.get("lockstep", "(none)")
			var bad: String = ""
			if not p.has("placements"):
				bad = "  [NO placements]"
			if pc == 0:
				bad += "  [EMPTY]"
			print("  %2d  %-22s  placements=%-3d  lockstep=%s%s" % [idx, nm, pc, str(lock), bad])
		else:
			print("  %2d  NON-DICT ENTRY" % idx)
		idx += 1
	print("=== END ===")
