extends SceneTree

# Same pattern as capture_all_screens.gd, but for the dev/test surfaces.

const OUT_DIR := "res://captures/screens_dev"

const SCREENS := [
	{"name": "dev_01_feature_showcase",  "scene": "res://scenes/dev/feature_showcase.tscn",   "settle": 1.0},
	{"name": "dev_02_maneuver_sim",      "scene": "res://scenes/dev/maneuver_sim.tscn",       "settle": 0.8},
	{"name": "dev_03_movement_test",     "scene": "res://scenes/dev/movement_test.tscn",      "settle": 0.8},
	{"name": "dev_04_parallax_tuner",    "scene": "res://scenes/dev/parallax_tuner.tscn",     "settle": 0.8},
	{"name": "dev_05_resolution_preview","scene": "res://scenes/dev/resolution_preview.tscn", "settle": 0.8},
	{"name": "dev_06_shield_pips_demo",  "scene": "res://scenes/dev/shield_pips_demo.tscn",   "settle": 0.6},
	{"name": "dev_07_enemy_bench",       "scene": "res://scenes/dev/enemy_bench.tscn",        "settle": 0.8},
	{"name": "dev_08_debug_testbed",     "scene": "res://scenes/debug_testbed.tscn",          "settle": 0.8},
	{"name": "dev_09_hangar",            "scene": "res://scenes/hangar.tscn",                 "settle": 0.8},
	{"name": "dev_10_enemy_codex",       "scene": "res://scenes/enemy_codex.tscn",            "settle": 0.8},
]


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for entry in SCREENS:
		await _capture_one(entry)
	print("[dev-screens] captured %d -> %s" % [SCREENS.size(), OUT_DIR])
	quit()


func _capture_one(entry: Dictionary) -> void:
	var path: String = entry.scene
	var name: String = entry.name
	var settle: float = entry.get("settle", 0.6)
	var ps: PackedScene = load(path)
	if ps == null:
		print("[dev-screens] SKIP %s - load failed: %s" % [name, path])
		return
	var inst: Node = ps.instantiate()
	if inst == null:
		print("[dev-screens] SKIP %s - instantiate failed" % name)
		return
	root.add_child(inst)
	await create_timer(settle).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("[dev-screens] SKIP %s - null image" % name)
		inst.queue_free()
		return
	var out_path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("[dev-screens] wrote %s" % out_path)
	inst.queue_free()
	await create_timer(0.2).timeout
