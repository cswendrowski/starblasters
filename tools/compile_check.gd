extends SceneTree

# Compile EVERY .gd under res://scripts so scripts only ever loaded at RUNTIME are
# gated too. parse_check.ps1 boots the user-reachable SCENES, but scripts that are
# instantiated dynamically mid-game (enemy_core via wave.enemy_scene.instantiate(),
# bosses, projectiles, effects) are never touched by a 2-frame headless boot — so a
# parse error there ships silently. (2026-06-04: a non-constant `const` in
# enemy_core.gd failed to load; every enemy_core enemy silently failed to spawn, and
# parse_check passed because main.tscn never instantiated an enemy in 2 frames.)
#
# A broken .gd makes load() print "Failed to load script ... Parse error" to stderr
# and return null. We collect failures, print them, and quit(1) so parse_check can
# gate on the exit code. NOTE: best-effort — a stale script cache can mask a freshly
# broken source until reimport; the common case (editor reimports the broken save)
# is caught. Run: godot --headless --script res://tools/compile_check.gd

func _init() -> void:
	var failed: Array = []
	var total: int = 0
	var stack: Array = ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with("."):
				var p: String = d.path_join(entry)
				if dir.current_is_dir():
					stack.append(p)
				elif entry.ends_with(".gd"):
					total += 1
					var s = load(p)
					if s == null or not (s is GDScript):
						failed.append(p)
			entry = dir.get_next()
		dir.list_dir_end()
	for f in failed:
		printerr("COMPILE FAIL: ", f)
	print("COMPILE CHECK: %d scripts checked, %d failed" % [total, failed.size()])
	quit(0 if failed.is_empty() else 1)
