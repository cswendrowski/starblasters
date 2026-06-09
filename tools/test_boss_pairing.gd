extends SceneTree

# Boss never-pair enforcement (already in run_state._pick_row_bosses + _BOSS_CONFLICTS).
# Confirm sector 2/3 rosters avoid forbidden pairs across many seeds. (Sector 1's pool
# is exactly 3 bosses for 3 slots, so its conflicts are pool-limited by design.)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")
	var conflicts: Dictionary = run._BOSS_CONFLICTS
	var rng := RandomNumberGenerator.new()
	for sector in [2, 3]:
		var bad := 0
		for s in range(60):
			rng.seed = sector * 10000 + s
			var picks: Array = run._pick_row_bosses(sector, rng, [])
			for i in picks.size():
				for j in range(i + 1, picks.size()):
					var a: String = String(picks[i])
					var b: String = String(picks[j])
					var ca: Array = conflicts.get(a, [])
					var cb: Array = conflicts.get(b, [])
					if ca.has(b) or cb.has(a):
						bad += 1
		_assert(bad == 0, "sector %d: no forbidden boss pairs over 60 seeds (got %d)" % [sector, bad])

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
