extends SceneTree

# Phase 3: outposts are no longer POIs. Generate several sectors and confirm zero
# OUTPOST nodes appear in the procedural POI rows.

const SectorNode = preload("res://scripts/sector_node.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")
	var total_pois := 0
	var outposts := 0
	for s in range(1, 4):
		run.new_run()
		run.start_new_sector(s, 1234 + s * 77)
		var cache: Dictionary = run.sector_map_cache
		for row in cache.get("rows", []):
			for poi in row.get("pois", []):
				total_pois += 1
				if int(poi.node_type) == int(SectorNode.NodeType.OUTPOST):
					outposts += 1
	_assert(total_pois > 0, "generated POIs across 3 sectors (%d)" % total_pois)
	_assert(outposts == 0, "ZERO outpost POIs (found %d)" % outposts)
	print("[test] %d POIs generated, %d outposts" % [total_pois, outposts])
	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
