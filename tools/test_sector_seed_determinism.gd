extends SceneTree

# Locks in the invariant the sector-map seed fix depends on (sector_map_v3
# _advance_if_complete now passes a DETERMINISTIC `run_seed + sectors_cleared`
# seed instead of `randi()`): re-rolling the SAME sector with the SAME seed must
# reproduce the same boss picks AND must NOT double-consume the boss pool
# (start_new_sector's dedup append at run_state.gd:494). The old randi() path
# disagreed with _ensure_sector_cache's formula, so a regen picked different
# bosses that got appended too — shrinking the pool toward forced repeats.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")
	run.new_run()

	# --- 1. Same (sector, seed) twice → identical bosses, no pool growth. ---
	var seed_value: int = run.run_seed + run.sectors_cleared  # the production formula
	run.start_new_sector(2, seed_value)
	var bosses_a: Array = _boss_scenes_of(run.sector_map_cache)
	var used_after_first: int = run.used_boss_scenes.size()

	run.start_new_sector(2, seed_value)
	var bosses_b: Array = _boss_scenes_of(run.sector_map_cache)
	var used_after_second: int = run.used_boss_scenes.size()

	_assert(bosses_a == bosses_b, "same (sector,seed) re-roll reproduces the same bosses (%s)" % [bosses_a])
	_assert(used_after_first == used_after_second,
		"re-roll does NOT double-consume the boss pool (%d -> %d)" % [used_after_first, used_after_second])
	_assert(int(run.sector_map_cache.get("seed", -999)) == seed_value,
		"cache records the seed it was built from")

	# --- 2. run_seed is stable (the fix removed the mid-run randi() clobber). ---
	var seed_before: int = run.run_seed
	run.sectors_cleared += 1
	var next_seed: int = run.run_seed + run.sectors_cleared
	run.start_new_sector(run.sectors_cleared + 1, next_seed)
	_assert(run.run_seed == seed_before, "run_seed unchanged across a sector advance")

	# --- 3. Distinct seeds DO change generation (proves the seed is actually ---
	# consumed, not ignored — assertion 1 alone would pass even on constant output).
	# Fingerprint the WHOLE cache (bosses + every POI id/type/pos) so the output
	# space is huge and a false collision across two seeds is negligible.
	run.new_run()
	run.start_new_sector(2, 1111)
	var fp_a: String = _fingerprint(run.sector_map_cache)
	run.new_run()
	run.start_new_sector(2, 1111)
	_assert(_fingerprint(run.sector_map_cache) == fp_a, "same seed → identical full-cache fingerprint")
	run.new_run()
	run.start_new_sector(2, 9999)
	var fp_b: String = _fingerprint(run.sector_map_cache)
	if fp_a == fp_b:
		print("[test]   fp_1111 = ", fp_a)
		print("[test]   fp_9999 = ", fp_b)
	_assert(fp_a != fp_b, "different seeds → different sector layout (seed is consumed)")

	print("[test] ALL PASS")
	quit()


func _boss_scenes_of(cache: Dictionary) -> Array:
	var out: Array = []
	for row in cache.get("rows", []):
		out.append(String(row.get("boss", {}).get("boss_scene", "")))
	return out


# A stable string fingerprint of the whole sector layout: every row's boss +
# each POI's id, node_type, and position. Large output space → two distinct
# seeds colliding on it is effectively impossible.
func _fingerprint(cache: Dictionary) -> String:
	var parts: Array = []
	for row in cache.get("rows", []):
		parts.append(String(row.get("boss", {}).get("boss_scene", "")))
		for poi in row.get("pois", []):
			parts.append("%s:%d:%s" % [String(poi.get("id", "")), int(poi.get("node_type", -1)), str(poi.get("pos", Vector2.ZERO))])
	return "|".join(parts)


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
