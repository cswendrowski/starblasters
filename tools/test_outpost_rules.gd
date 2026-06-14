extends SceneTree

# Definitive validation for sector-map outpost rules. Replicates start_new_sector
# EXACTLY (same rng consumption order), measures the per-row-capped outpost count
# BEFORE _enforce_outpost_rules and the final count AFTER, on the SAME rows.
# Usage: godot --headless --script res://tools/test_outpost_rules.gd

const OUTPOST := 1  # SectorNodeType.OUTPOST

func _count(rows: Array, capped: bool) -> int:
	var total := 0
	for row in rows:
		var n := 0
		for poi in row.pois:
			if int(poi.node_type) == OUTPOST:
				n += 1
		total += (mini(n, 1) if capped else n)
	return total

func _init() -> void:
	var RunState = load("res://scripts/autoload/run_state.gd")
	var trials := 600
	var fails := 0
	var row_dupes := 0
	var pre := {}   # per-row-capped count BEFORE enforce
	var post := {}  # final count AFTER enforce

	var anchors := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]
	for i in trials:
		var run = RunState.new()  # fresh — no used_boss_scenes accumulation
		run.sectors_cleared = 0
		run.run_seed = 777
		var seed_value := 1000 + i

		# --- Replicate start_new_sector up to (but not including) the enforce call.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var modifier_count: int = clampi(1 + run.sectors_cleared, 1, 6)
		var pool: Array = run._pick_sector_modifiers(rng, modifier_count)
		var boss_scenes: Array = run._pick_row_bosses(1, rng, run.used_boss_scenes)
		var rows: Array = []
		for r in range(3):
			rows.append({
				"anchor": anchors[r],
				"boss": {"id": "b%d" % r, "node_type": 3, "pos": Vector2(448, 64), "completed": false, "modifiers": []},
				"pois": run._gen_row_pois(rng, 1, r, anchors[r], pool),
			})

		var pre_count := _count(rows, true)
		pre[pre_count] = int(pre.get(pre_count, 0)) + 1

		run._enforce_outpost_rules(rows, rng)

		var post_count := _count(rows, false)
		post[post_count] = int(post.get(post_count, 0)) + 1
		for row in rows:
			var c := 0
			for poi in row.pois:
				if int(poi.node_type) == OUTPOST: c += 1
			if c > run.OUTPOST_MAX_PER_ROW:
				row_dupes += 1; fails += 1
		if post_count < run.OUTPOST_MIN_PER_SECTOR or post_count > run.OUTPOST_MAX_PER_SECTOR:
			fails += 1

	# End-to-end: real start_new_sector on a FRESH instance per trial.
	var e2e := {}
	var e2e_dupes := 0
	for i in trials:
		var run2 = RunState.new()
		run2.sectors_cleared = 0
		run2.run_seed = 777
		run2.start_new_sector(1, 1000 + i)
		var t := 0
		for row in run2.sector_map_cache.rows:
			var c := 0
			for poi in row.pois:
				if int(poi.node_type) == OUTPOST: c += 1
			if c > 1: e2e_dupes += 1
			t += c
		e2e[t] = int(e2e.get(t, 0)) + 1

	print("trials=%d  row_dupes=%d  total_fails=%d" % [trials, row_dupes, fails])
	print("PRE  enforce (per-row-capped): %s" % str(pre))
	print("POST enforce (final):          %s" % str(post))
	print("E2E start_new_sector (fresh):  %s  dupes=%d" % [str(e2e), e2e_dupes])
	if fails == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
