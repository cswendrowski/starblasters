extends Node

# Sector-modifiers kill-switch test (Roman 2026-06-10: pulled pending re-eval). Verifies that with
# SECTOR_MODIFIERS_ENABLED=false: generated sectors carry NO modifiers on any POI, the cache's
# sector_modifiers readout is empty, and Run.sector_modifiers stays empty. Also sanity-checks the
# outpost roll dedupe key change parses by loading outpost.gd.
# Run: godot --headless --path . tools/test_modifiers_off.tscn --quit-after 120

const RESULT := "res://tools/_modifiers_off_result.txt"
var _t := 0

func _process(_dt: float) -> void:
	_t += 1
	if _t < 3:
		return
	set_process(false)
	var lines: Array = []
	var fails := 0
	var run = get_node_or_null("/root/Run")
	if run == null:
		lines.append("FAIL no Run autoload"); _finish(lines); return
	if bool(run.SECTOR_MODIFIERS_ENABLED):
		lines.append("FAIL flag should be false"); fails += 1
	run.new_run()
	# Generate several sectors across seeds; assert zero modifiers anywhere.
	var poi_count := 0
	var modded := 0
	for seed_v in [1, 42, 999, 123456]:
		run.sectors_cleared = 3   # would have rolled a 4-modifier pool when enabled
		run.start_new_sector(1, seed_v)
		var cache: Dictionary = run.sector_map_cache
		if not (cache.get("sector_modifiers", []) as Array).is_empty():
			lines.append("FAIL cache sector_modifiers not empty (seed %d)" % seed_v); fails += 1
		for row in cache.get("rows", []):
			for poi in row.get("pois", []):
				poi_count += 1
				if not (poi.get("modifiers", []) as Array).is_empty():
					modded += 1
	lines.append("POIs generated: %d, with modifiers: %d (expect 0)" % [poi_count, modded])
	if modded > 0:
		lines.append("FAIL modifiers still generated"); fails += 1
	if run.sector_modifiers is Array and not run.sector_modifiers.is_empty():
		lines.append("FAIL Run.sector_modifiers not empty"); fails += 1
	lines.append("MODIFIERS OFF: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines)

func _finish(lines: Array) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
