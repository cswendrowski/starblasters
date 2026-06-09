extends SceneTree

# Run Summary Phase 1: RunStats core + Run Timer.
# A) Run layer — new_run reset, stat_add, record_kill tally, history record.
# B) Death screen — run_summary shows the new stats.
# C) main integration — timer accumulates while playing; damaged signal tallies.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")

	# --- A. Run layer ---
	run.new_run()
	_assert(run.run_time_seconds == 0.0, "run_time_seconds reset to 0")
	_assert(int(run.run_stats.get("damage_hull", -1)) == 0, "run_stats reset (damage_hull=0)")
	run.stat_add("damage_hull", 2)
	run.stat_add("damage_hull", 1)
	_assert(int(run.run_stats["damage_hull"]) == 3, "stat_add accumulates (3)")
	run.record_kill(50)
	_assert(int(run.run_stats["bounty_gained"]) == 50, "record_kill tallies bounty_gained")
	run.run_time_seconds = 125.0
	run.stat_add("asteroids", 7)
	run.record_run_history("died")
	var hist: Array = run.load_run_history()
	var last: Dictionary = hist[hist.size() - 1]
	_assert(int(last.get("time", -1)) == 125, "history record carries time")
	_assert(int(last.get("asteroids", -1)) == 7, "history record carries asteroids")
	_assert(last.has("damage_shield") and last.has("damage_hull"), "history record carries damage stats")

	# --- B. Death screen renders the stats ---
	var rs = load("res://scenes/run_summary.tscn").instantiate()
	root.add_child(rs)   # NOT current_scene → skips record_run_history()
	await process_frame
	await process_frame
	var txt: String = String(rs.stats_label.text)
	_assert(txt.contains("Time: 2:05"), "summary shows formatted time (2:05) — got: %s" % txt.split("\n")[0])
	_assert(txt.contains("Damage taken:"), "summary shows damage taken")
	_assert(txt.contains("Bounty earned:"), "summary shows bounty earned")
	rs.free()
	await process_frame

	# --- C. main integration: timer + damage hook ---
	change_scene_to_file("res://scenes/main.tscn")
	for i in range(10):
		await process_frame
	var main = current_scene
	main.playing = true              # force active (skip the intro wait)
	main._level_time = 0.0
	for i in range(15):
		await process_frame
	_assert(main._level_time > 0.0, "level timer accumulates while playing (%.3f)" % main._level_time)
	# Damage tally via the connected Player.damaged signal.
	run.run_stats["damage_shield"] = 0
	run.run_stats["damage_hull"] = 0
	if main.player != null and is_instance_valid(main.player):
		main.player.damaged.emit(0)  # shield
		main.player.damaged.emit(1)  # hull
		main.player.damaged.emit(1)  # hull
		await process_frame
		_assert(int(run.run_stats["damage_shield"]) == 1, "shield hit tallied (1)")
		_assert(int(run.run_stats["damage_hull"]) == 2, "hull hits tallied (2)")
	else:
		print("[test] (skipped damage tally — no player)")

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
