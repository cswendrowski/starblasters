extends SceneTree

# Sanity-check that resources/levels/test_level.tres + its referenced
# waves load and produce the expected shape.

func _init() -> void:
	const PATH := "res://resources/levels/test_level.tres"
	if not ResourceLoader.exists(PATH):
		push_error("missing: %s" % PATH)
		quit(1)
		return
	var lvl = load(PATH)
	if lvl == null:
		push_error("load returned null: %s" % PATH)
		quit(1)
		return
	print("level: ", lvl.level_name)
	print("waves: ", lvl.waves.size())
	for i in lvl.waves.size():
		var w = lvl.waves[i]
		print("  wave[%d]: enemy=%s count=%d delay=%.2f interval=%.2f silent=%s" % [
			i,
			w.enemy_scene.resource_path if w.enemy_scene else "<null>",
			w.count,
			w.spawn_delay,
			w.spawn_interval,
			w.silent,
		])
	quit(0)
