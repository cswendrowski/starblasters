extends SceneTree

# One-shot sim for the outpost-density clamp + modifier generation.
# Usage:
#   godot --path . --headless -s tools/sim_outpost_density.gd --quit
#
# Loops N sectors per `sectors_cleared` value, counts outposts per sector and
# modifiers per POI. Prints histograms for designer verification.

const SectorNodeType = preload("res://scripts/sector_node.gd").NodeType

func _init() -> void:
	# Autoloads aren't registered when running via -s; instantiate Run directly.
	var RunScript = load("res://scripts/autoload/run_state.gd")
	var Run = RunScript.new()
	root.add_child(Run)
	var sample_n: int = 1000
	print("=== Outpost density (N=%d sectors) ===" % sample_n)
	var hist := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Use sectors_cleared=0 so mod pool is the typical sector-1 size (1 modifier).
	Run.sectors_cleared = 0
	for i in range(sample_n):
		Run.start_new_sector(1, rng.randi())
		var count: int = 0
		for row in Run.sector_map_cache.rows:
			for poi in row.pois:
				if int(poi.node_type) == int(SectorNodeType.OUTPOST):
					count += 1
		hist[clampi(count, 0, 8)] = hist.get(clampi(count, 0, 8), 0) + 1
	for k in [0,1,2,3,4,5,6,7,8]:
		var pct: float = 100.0 * float(hist[k]) / float(sample_n)
		print("  %d outposts: %4d (%5.1f%%)" % [k, hist[k], pct])

	print("")
	print("=== Modifier generation (sectors_cleared 0..6) ===")
	for cleared in range(7):
		Run.sectors_cleared = cleared
		Run.start_new_sector(cleared + 1, 12345 + cleared)
		var pool: Array = Run.sector_map_cache.get("sector_modifiers", [])
		var poi_count: int = 0
		var with_mod: int = 0
		var mod_hist := {}
		for row in Run.sector_map_cache.rows:
			for poi in row.pois:
				poi_count += 1
				var mods: Array = poi.get("modifiers", [])
				if not mods.is_empty():
					with_mod += 1
					for m in mods:
						mod_hist[m] = mod_hist.get(m, 0) + 1
		print("  cleared=%d  pool_size=%d  pool=%s  POIs=%d  with_mod=%d  per-mod=%s" % [
			cleared, pool.size(), str(pool), poi_count, with_mod, str(mod_hist)
		])

	quit()
