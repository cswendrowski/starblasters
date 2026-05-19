extends SceneTree

# Boots each user-facing scene headless and saves a PNG screenshot to
# captures/screens/. Used to verify resolution + layout after the 320x400
# internal-resolution shift.
#
# The viewport at capture time is the project's configured size, so each PNG
# is the native pixel grid (320x400). Inspect at 2x or 3x in an image viewer
# to see what the player actually sees on screen.

const OUT_DIR := "res://captures/screens"
const SETTLE := 0.6

const SCREENS := [
	{"name": "01_main_menu",      "scene": "res://scenes/main_menu.tscn",     "settle": 0.6},
	{"name": "02_onboarding",     "scene": "res://scenes/onboarding.tscn",    "settle": 0.6},
	{"name": "03_sector_map_v2",  "scene": "res://scenes/sector_map_v2.tscn", "settle": 0.8},
	{"name": "04_outpost",        "scene": "res://scenes/outpost.tscn",       "settle": 0.6},
	{"name": "05_signal_event",   "scene": "res://scenes/signal_event.tscn",  "settle": 0.6},
	{"name": "06_combat",         "scene": "res://scenes/main.tscn",          "settle": 2.0},
	{"name": "07_pause_menu",     "scene": "res://scenes/pause_menu.tscn",    "settle": 0.4},
	{"name": "08_cleared_summary","scene": "res://scenes/cleared_summary.tscn","settle": 0.6},
	{"name": "09_run_summary",    "scene": "res://scenes/run_summary.tscn",   "settle": 0.6},
	{"name": "10_dev_menu",       "scene": "res://scenes/dev_menu.tscn",      "settle": 0.4},
]


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for entry in SCREENS:
		await _capture_one(entry)
	print("[screens] captured %d scenes -> %s" % [SCREENS.size(), OUT_DIR])
	quit()


func _capture_one(entry: Dictionary) -> void:
	var path: String = entry.scene
	var name: String = entry.name
	var settle: float = entry.get("settle", SETTLE)
	var ps: PackedScene = load(path)
	if ps == null:
		print("[screens] SKIP %s — could not load %s" % [name, path])
		return
	var inst: Node = ps.instantiate()
	if inst == null:
		print("[screens] SKIP %s — could not instantiate" % name)
		return
	root.add_child(inst)
	await create_timer(settle).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var out_path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("[screens] wrote %s" % out_path)
	inst.queue_free()
	await create_timer(0.2).timeout
