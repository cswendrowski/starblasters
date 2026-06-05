extends SceneTree

# Path-phase firing (construction §8). Verifies:
#   Zones.band_progress  — 0 at/above entry (y40), 1 at/below departure (y195),
#                          linear between, clamped.
#   path_phase_capable   — monotonic descenders (straight_down, s_curve, lane_path)
#                          opt IN; reversing/holding patterns (advance_retreat,
#                          loiter) and the base stay OUT.
#   fire mapping         — default phases [0.35,0.75] map to sane fire Ys (~94/~156),
#                          both safely above the departure band (cease-fire) so a
#                          descender never plinks point-blank.
# Run: godot --headless --script res://tools/test_path_phase.gd

const RESULT := "res://tools/_path_phase_result.txt"
const Zones := preload("res://scripts/zones.gd")
const Base := preload("res://scripts/enemies/movement_pattern.gd")
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const SCurve := preload("res://scripts/enemies/patterns/s_curve.gd")
const LanePath := preload("res://scripts/enemies/patterns/lane_path.gd")
const AdvanceRetreat := preload("res://scripts/enemies/patterns/advance_retreat.gd")
const Loiter := preload("res://scripts/enemies/patterns/loiter.gd")


func _init() -> void:
	var lines: Array = []
	var fails: int = 0

	# --- band_progress ----------------------------------------------------
	var cases := {
		20.0: 0.0, 40.0: 0.0, 117.5: 0.5, 195.0: 1.0, 260.0: 1.0,
	}
	for y in cases:
		var got: float = Zones.band_progress(y)
		if absf(got - cases[y]) > 0.01:
			lines.append("FAIL band_progress(%s)=%.3f expected %.3f" % [y, got, cases[y]]); fails += 1

	# --- capability flags -------------------------------------------------
	var capable := {
		"straight_down": StraightDown.new().path_phase_capable(),
		"s_curve": SCurve.new().path_phase_capable(),
		"lane_path": LanePath.new().path_phase_capable(),
	}
	var incapable := {
		"base": Base.new().path_phase_capable(),
		"advance_retreat": AdvanceRetreat.new().path_phase_capable(),
		"loiter": Loiter.new().path_phase_capable(),
	}
	for k in capable:
		if not capable[k]:
			lines.append("FAIL %s should be path_phase_capable" % k); fails += 1
	for k in incapable:
		if incapable[k]:
			lines.append("FAIL %s must NOT be path_phase_capable" % k); fails += 1

	# --- fire-Y mapping (documents the default) ---------------------------
	var span: float = Zones.DEPARTURE_START - Zones.ENTRY_END
	var y0: float = Zones.ENTRY_END + 0.35 * span
	var y1: float = Zones.ENTRY_END + 0.75 * span
	if y1 >= Zones.DEPARTURE_START:
		lines.append("FAIL last phase fires in/after departure band (no cease-fire)"); fails += 1
	lines.append("default phases fire at y=%.1f and y=%.1f (band %.0f-%.0f)" % [
		y0, y1, Zones.ENTRY_END, Zones.DEPARTURE_START])

	lines.append("PATH PHASE TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
