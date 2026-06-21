extends SceneTree

# Headless smoke for LevelLauncher.go() (Roman 2026-06-19). Drives the full flow against a LIGHT
# target scene so we exercise the whole coroutine without combat's heavy boot:
#   threaded preload -> loading screen becomes current scene -> min-dwell -> fly_off ->
#   flight_complete -> cover-only swap -> land on target.
# Verifies no errors + that we actually reach the target. Run via:
#   godot --headless -s res://tools/test_loading_launcher.gd

const LevelLauncher = preload("res://scripts/systems/level_launcher.gd")
const TARGET := "res://scenes/credits.tscn"   # light HD scene, cheap to load + boot

var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Bare start scene so the launcher's "wait for LoadingScreen to be current" gate is meaningful
	# (a real start scene that happened to be a LoadingScreen would defeat the gate).
	var start_node := Node.new()
	start_node.name = "TestStart"
	root.add_child(start_node)
	current_scene = start_node
	await process_frame

	print("[test] launching -> ", TARGET)
	LevelLauncher.go(self, TARGET)

	var last := ""
	var saw_loading := false
	var start_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 9000:
		await process_frame
		var cur: Node = current_scene
		var path: String = cur.scene_file_path if cur != null else "<null>"
		if path != last:
			print("[test] current scene -> ", path if path != "" else "<bare>")
			last = path
		if cur != null and cur is LoadingScreen:
			saw_loading = true
		if path == TARGET:
			_done = true
			break

	if _done and saw_loading:
		print("[test] PASS: passed through the loading screen and landed on the target")
	elif _done:
		printerr("[test] PARTIAL: reached target but never saw the loading screen as current")
	else:
		printerr("[test] FAIL: did not reach target; stuck at ", last)
	quit(0 if (_done and saw_loading) else 1)
