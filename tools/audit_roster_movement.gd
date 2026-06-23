extends SceneTree

# One-shot audit: list roster ENTRIES whose scene is in the eligibility matrix but
# whose "movement" disagrees with the matrix identity (the producer-shadow). Used to
# drive the roster->matrix sync. Prints "<scene> | movement=<x> -> identity=<y>".

func _initialize() -> void:
	var rs: GDScript = load("res://scripts/levels/enemy_roster.gd")
	var elig: GDScript = load("res://scripts/levels/pattern_eligibility.gd")
	var entries: Array = rs.get_script_constant_map().get("ENTRIES", [])
	var data: Dictionary = elig.get_script_constant_map().get("DATA", {})
	var mismatches: Array = []
	var seen: Dictionary = {}
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var scene: String = str(e.get("scene", ""))
		if not data.has(scene):
			continue
		var identity: String = str(data[scene].get("identity", ""))
		var mv: String = str(e.get("movement", ""))
		if identity != "" and mv != identity:
			var key: String = scene + "|" + mv
			if not seen.has(key):
				seen[key] = true
				mismatches.append("%s | movement=%s -> identity=%s" % [scene.get_file(), mv, identity])
	print("=== ROSTER<->MATRIX MOVEMENT MISMATCHES (%d unique scene/movement) ===" % mismatches.size())
	for m in mismatches:
		print(m)
	print("=== END ===")
	quit()
