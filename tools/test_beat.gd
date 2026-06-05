extends SceneTree

# Shared beat (Beat) — global firing tempo that path-phase shots quantize to.
# Verifies next_beat_time is always strictly in (t, t+PERIOD], lands on the grid,
# and that two nearby ready-times collapse onto the SAME beat (the volley property).
# Run: godot --headless --script res://tools/test_beat.gd

const RESULT := "res://tools/_beat_result.txt"
const Beat := preload("res://scripts/beat.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0
	var P: float = Beat.PERIOD

	# next_beat_time is strictly future and within one period.
	for t in [0.0, 0.1, P, P * 1.5, 1.0, 3.333]:
		var nb: float = Beat.next_beat_time(t)
		if nb <= t:
			lines.append("FAIL next_beat_time(%.3f)=%.3f not > t" % [t, nb]); fails += 1
		if nb > t + P + 0.0001:
			lines.append("FAIL next_beat_time(%.3f)=%.3f > t+PERIOD" % [t, nb]); fails += 1
		# Lands on the grid (multiple of PERIOD).
		var k: float = nb / P
		if absf(k - round(k)) > 0.001:
			lines.append("FAIL next_beat_time(%.3f)=%.3f not on grid" % [t, nb]); fails += 1

	# Volley property: two ready-times within the same beat window snap together.
	var a: float = Beat.next_beat_time(1.00)
	var b: float = Beat.next_beat_time(1.00 + P * 0.3)  # 0.3 of a beat later, same window
	if absf(a - b) > 0.0001:
		lines.append("FAIL nearby ready-times did not collapse onto one beat (%.3f vs %.3f)" % [a, b]); fails += 1

	# Crossing a boundary lands on the NEXT beat (distinct volley).
	var c: float = Beat.next_beat_time(1.00 + P * 1.2)
	if c <= a:
		lines.append("FAIL ready-time past the boundary did not advance to next beat"); fails += 1

	# index monotonic non-decreasing over time.
	if Beat.index(2.0 * P) < Beat.index(P):
		lines.append("FAIL index not monotonic"); fails += 1

	lines.append("PERIOD=%.3f  next_beat_time(1.0)=%.3f  collapse a=b=%.3f  nextwindow=%.3f" % [P, Beat.next_beat_time(1.0), a, c])
	lines.append("BEAT TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
