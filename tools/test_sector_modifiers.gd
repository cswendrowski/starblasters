extends SceneTree

# Sector modifiers (2026-06-09): each POI rolls its modifier independently from the FULL range, so
# a single sector shows variety (not one repeated modifier) and the full set appears across sectors.
# Run: godot --headless --script res://tools/test_sector_modifiers.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var run = root.get_node("/root/Run")
	var lines: Array = []
	var fails := 0

	# 1. A single sector's POIs should show MULTIPLE distinct modifiers (not all the same).
	run.new_run()
	run.run_seed = 4242
	run.start_new_sector(1, 4242)
	var in_sector: Dictionary = {}
	for row in run.sector_map_cache.get("rows", []):
		for poi in row.get("pois", []):
			for m in poi.get("modifiers", []):
				in_sector[m] = true
	lines.append("sector-1 distinct POI modifiers: %s" % str(in_sector.keys()))
	if in_sector.size() < 2:
		lines.append("FAIL sector shows < 2 distinct modifiers (%d)" % in_sector.size()); fails += 1

	# 2. Across 30 sectors, the FULL modifier range should appear.
	var seen: Dictionary = {}
	for s in range(30):
		run.new_run()
		var rs: int = 100 + s * 137
		run.run_seed = rs
		run.start_new_sector(1, rs)
		for row in run.sector_map_cache.get("rows", []):
			for poi in row.get("pois", []):
				for m in poi.get("modifiers", []):
					seen[m] = true
	lines.append("modifiers seen across 30 sectors (%d/%d): %s" % [seen.size(), run.ALL_SECTOR_MODIFIERS.size(), str(seen.keys())])
	if seen.size() < run.ALL_SECTOR_MODIFIERS.size():
		lines.append("FAIL not the full range (%d/%d)" % [seen.size(), run.ALL_SECTOR_MODIFIERS.size()]); fails += 1

	# 3. Outpost readout (cache.sector_modifiers) reflects the actual POI modifiers.
	run.new_run(); run.run_seed = 9; run.start_new_sector(1, 9)
	lines.append("cache.sector_modifiers = %s" % str(run.sector_map_cache.get("sector_modifiers", [])))

	lines.append("SECTOR MODIFIERS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
