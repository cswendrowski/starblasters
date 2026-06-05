extends SceneTree

# M5 step 3: opener-pool width. After pulling firecore + strafer to unlock_depth 0,
# the sector-1 node-0 COMMON pool should contain >= 5 distinct chaff scenes (was 3:
# dart/bomb_drone/drifter). Run: godot --headless --script res://tools/test_opener_pool.gd

const RESULT := "res://tools/_opener_pool_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0
	# entries_eligible(COMMON, sector_idx=1, sector_depth=0) == the opener pool.
	var pool: Array = Roster.entries_eligible(Roster.Tier.COMMON, 1, 0)
	var scenes: Dictionary = {}
	for e in pool:
		scenes[str(e.get("scene", "?")).get_file()] = true
	var names: Array = scenes.keys()
	names.sort()
	if names.size() < 5:
		lines.append("FAIL opener pool only %d types: %s" % [names.size(), str(names)]); fails += 1
	for must in ["enemy_firecore.tscn", "enemy_strafer.tscn"]:
		if not scenes.has(must):
			lines.append("FAIL %s not in opener pool" % must); fails += 1
	lines.append("opener COMMON types (%d): %s" % [names.size(), str(names)])
	lines.append("OPENER POOL TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
