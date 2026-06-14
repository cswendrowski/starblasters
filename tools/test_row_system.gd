extends SceneTree

# Headless verification that the DATA-GENERATION path actually runs and that
# the row-system bodies agree with the map's single-planet reference. parse_check
# false-passes compile errors and the capture used synthetic data, so without
# this _compute_row_system / _compute_poi_stellar / the boss edit are never run.

const MAP := preload("res://scripts/screens/sector_map_v3.gd")


func _init() -> void:
	# Autoloads are not yet attached during _init; defer until the tree is up.
	call_deferred("_run")


func _run() -> void:
	var fails: int = 0

	# Minimal synthetic cache: one row, boss at x=448, 4 POIs spread 128..432.
	# Run is an autoload — present under /root once the tree is initialized.
	var run := get_root().get_node("Run")
	run.run_seed = 12345
	run.sectors_cleared = 0
	run.sector_map_cache = {
		"rows": [{
			"anchor": Vector2(64, 64),
			"boss": {"id": "boss_0", "pos": Vector2(448, 64)},
			"pois": [
				{"id": "poi_a", "pos": Vector2(150, 64), "node_type": 0, "completed": false},
				{"id": "poi_b", "pos": Vector2(230, 64), "node_type": 0, "completed": false},
				{"id": "poi_c", "pos": Vector2(320, 64), "node_type": 0, "completed": false},
				{"id": "poi_d", "pos": Vector2(410, 64), "node_type": 0, "completed": false},
			],
		}],
	}

	var map := MAP.new()
	get_root().add_child(map)  # so get_node("/root/Run") resolves inside the script

	var rows: Array = run.sector_map_cache.rows
	var pois: Array = rows[0].pois
	var checked_planet_match: int = 0

	for poi in pois:
		var stellar: Dictionary = map._compute_poi_stellar(poi, 0)
		var system: Array = stellar.get("system", [])
		if system.is_empty():
			push_error("[test] empty system for %s" % poi.id); fails += 1; continue
		# Body 0 must be the star.
		if String(system[0].get("kind", "")) != "star":
			push_error("[test] body0 not star for %s" % poi.id); fails += 1
		# Cap: star + up to SYSTEM_MAX_PLANETS planets.
		if system.size() > 1 + MAP.SYSTEM_MAX_PLANETS:
			push_error("[test] system over cap (%d) for %s" % [system.size(), poi.id]); fails += 1
		# AGREEMENT: if this POI itself is a PLANET node, its own body must appear
		# in the system with planet_idx == the top-level (map-reference) key.
		var top_idx: int = int(stellar.get("planet_idx", -1))
		if top_idx >= 0:  # -1 means asteroid-field (no planet)
			var found: bool = false
			for b in system:
				if String(b.get("kind", "")) == "planet" \
						and int(b.get("planet_seed", 0)) == abs(hash(poi.id)):
					found = true
					if int(b.get("planet_idx", -99)) != top_idx:
						push_error("[test] AGREEMENT FAIL %s: system idx %d != top %d" \
							% [poi.id, int(b.get("planet_idx", -99)), top_idx]); fails += 1
					break
			if found:
				checked_planet_match += 1

	# Boss path: must return a star-only system without crashing.
	var boss_stellar: Dictionary = map._compute_boss_stellar(0)
	var boss_sys: Array = boss_stellar.get("system", [])
	if boss_sys.size() != 1 or String(boss_sys[0].get("kind", "")) != "star":
		push_error("[test] boss system not star-only: %s" % str(boss_sys)); fails += 1

	var summary: String = "planet-agreement bodies verified: %d | %s" % [
		checked_planet_match,
		"ALL CHECKS PASS" if fails == 0 else "FAILURES: %d" % fails]
	print("[test] ", summary)
	var f := FileAccess.open("user://test_row_system_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(summary)
		f.close()
	quit(fails)
