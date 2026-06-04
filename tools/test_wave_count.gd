extends SceneTree

# Unit check for the M5 wave-count rule: 5-8 waves, scaling with node-in-sector
# (level_index) and sector_depth, soft-capped at 8.
# Run: godot --headless --script res://tools/test_wave_count.gd

const RESULT := "res://tools/_wave_count_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")


func _init() -> void:
	var log: Array = []
	# [sector_depth, level_index, expected]
	var checks := [
		[1, 0, 5],   # sector 1 node 1 -> floor 5
		[1, 1, 6],
		[1, 3, 8],   # scales within a sector
		[1, 5, 8],   # capped
		[3, 0, 7],   # deeper sector starts higher
		[5, 0, 8],   # capped
	]
	for c in checks:
		var got: int = WG._wave_count_for(c[0], c[1])
		if got != c[2]:
			log.append("FAIL wave_count(sd=%d, li=%d)=%d expected %d" % [c[0], c[1], got, c[2]])
	# Always within 5-8.
	for sd in range(1, 9):
		for li in range(0, 10):
			var n: int = WG._wave_count_for(sd, li)
			if n < 5 or n > 8:
				log.append("FAIL count=%d out of 5-8 (sd=%d, li=%d)" % [n, sd, li])
	if log.is_empty():
		log.append("WAVE_COUNT TEST: PASS")
	else:
		log.append("WAVE_COUNT TEST: FAIL")
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(log)))
		f.close()
	quit()
