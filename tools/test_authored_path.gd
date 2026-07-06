extends SceneTree

# Authored-path runtime test (2026-07-06). Builds each baked path from AuthoredPathLibrary, steps a
# stub enemy through compute_step for a full traversal, and asserts:
#   (1) DETERMINISM — two independent runs of the same path produce identical positions.
#   (2) CONSTANT ARC-SPEED — per-frame travel matches the snapped chassis speed within tolerance,
#       excluding dwell holds (0 travel) and the frame where the path ends (partial + exit overrun).
#   (3) PATH-PHASE CAPABILITY — monotone-y paths report path_phase_capable() true, non-monotone false.
#   (4) MIRROR + LANE-RELATIVE BOUNDS — a lane-relative path spawned on all 7 lanes, plain AND
#       mirrored, stays inside the Playfield X band. The runtime CLAMPS resolved X to the band (inset
#       one lane-half so the hull stays shootable, mirroring lane_path's amplitude clamp); this test
#       ASSERTS the clamp holds for every lane/mirror combination.
# Run: godot --headless --script res://tools/test_authored_path.gd

const RESULT := "res://tools/_authored_path_result.txt"
const AuthoredPath := preload("res://scripts/enemies/patterns/authored_path.gd")
const AuthoredPathLibrary := preload("res://scripts/enemies/patterns/authored_path_library.gd")
const Playfield := preload("res://scripts/systems/playfield.gd")
const Lanes := preload("res://scripts/systems/lanes.gd")
const Clarity := preload("res://scripts/systems/clarity.gd")

const DT := 1.0 / 60.0
const MOVE_SPEED := 180.0   # medium chassis
const X_MARGIN := 0.5       # px slack for the bounds assert (sub-pixel resolve rounding)


class Stub:
	extends Node2D
	var move_speed: float = 180.0


func _init() -> void:
	var lines: Array = []
	var fails: int = 0

	for name in AuthoredPathLibrary.names():
		var def: Dictionary = AuthoredPathLibrary.DATA[name]

		# --- (1) determinism ------------------------------------------------
		var run_a: Array = _traverse(name, Lanes.lane_center(3), false)
		var run_b: Array = _traverse(name, Lanes.lane_center(3), false)
		if run_a.size() != run_b.size():
			lines.append("FAIL [%s] determinism: length %d vs %d" % [name, run_a.size(), run_b.size()]); fails += 1
		else:
			var det := true
			for i in run_a.size():
				if (run_a[i] as Vector2).distance_to(run_b[i]) > 0.0001:
					det = false
					break
			if not det:
				lines.append("FAIL [%s] determinism: runs diverge" % name); fails += 1

		# --- (2) constant arc-speed ----------------------------------------
		# Measure the pattern's ARC-LENGTH advance per frame (its internal cursor), not the Euclidean
		# frame delta — at a sharp polyline corner a frame straddling two segments has a shorter
		# straight-line hop (chord-shortening) even though the arc-length step is constant. Constant
		# arc-speed is the real invariant; expected = snapped(move_speed * speed_scale) * DT.
		var expect: float = Clarity.snap_to_rung(MOVE_SPEED * float(def.get("speed_scale", 1.0))) * DT
		var arc: Array = _arc_advances(name)
		var worst: float = 0.0
		for a in arc:
			if float(a) < 0.0001:
				continue   # dwell hold or the terminal frame
			worst = maxf(worst, absf(float(a) - expect))
		if worst > 0.05:
			lines.append("FAIL [%s] arc-speed: worst arc-step err %.4f px (expect %.4f/frame)" % [name, worst, expect]); fails += 1

		# --- (3) path-phase capability -------------------------------------
		var mv := AuthoredPathLibrary.build(name)
		var mono: bool = AuthoredPath.is_monotone_y(def.get("waypoints", []))
		if mv.path_phase_capable() != mono:
			lines.append("FAIL [%s] path_phase_capable=%s but monotone_y=%s" % [name, mv.path_phase_capable(), mono]); fails += 1
		lines.append("[%s] mono=%s phase=%s scale=%.2f" % [name, mono, mv.path_phase_capable(), float(def.get("speed_scale", 1.0))])

		# --- (4) relative + mirror bounds across all 7 lanes ----------------
		if bool(def.get("relative", false)):
			for lane in Lanes.COUNT:
				for mir in [false, true]:
					var anchor: float = Lanes.lane_center(lane)
					var pts: Array = _traverse(name, anchor, mir)
					var min_x: float = 1e9
					var max_x: float = -1e9
					for p in pts:
						min_x = minf(min_x, (p as Vector2).x)
						max_x = maxf(max_x, (p as Vector2).x)
					if min_x < Playfield.X_MIN - X_MARGIN or max_x > Playfield.X_MAX + X_MARGIN:
						lines.append("FAIL [%s] lane %d mir=%s out of band: x[%.1f, %.1f] band[%.0f, %.0f]" % [
							name, lane, mir, min_x, max_x, Playfield.X_MIN, Playfield.X_MAX]); fails += 1

	lines.append("AUTHORED PATH TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	print("\n".join(PackedStringArray(lines)))
	quit()


# Per-frame arc-length advance of the pattern's internal cursor over a full traversal, EXCLUDING the
# final frame (which is a partial step + straight-line overrun past the last waypoint).
func _arc_advances(name: String) -> Array:
	var mv := AuthoredPathLibrary.build(name)
	var stub := Stub.new()
	stub.move_speed = MOVE_SPEED
	stub.position = Vector2(Lanes.lane_center(3), 0.0)
	mv.on_start(stub)
	var out: Array = []
	var prev_dist: float = mv._dist
	var total: float = mv._total_len
	var guard: int = 0
	while guard < 6000:
		guard += 1
		var step: Vector2 = mv.compute_step(stub, DT)
		stub.position += step
		# Once the cursor reaches total_len the path is exiting straight (constant, but not along the
		# curve) — stop measuring curve arc-steps there.
		if mv._dist >= total:
			break
		out.append(mv._dist - prev_dist)
		prev_dist = mv._dist
		if stub.position.y >= Playfield.Y_MAX + 8.0:
			break
	return out


# Step a path to completion, returning the per-frame position samples.
func _traverse(name: String, anchor_x: float, mirror: bool) -> Array:
	var mv := AuthoredPathLibrary.build(name)
	mv.mirrored = mirror
	var stub := Stub.new()
	stub.move_speed = MOVE_SPEED
	stub.position = Vector2(anchor_x, 0.0)
	mv.on_start(stub)   # teleports to the first waypoint
	var out: Array = [stub.position]
	var guard: int = 0
	while guard < 6000:
		guard += 1
		var step: Vector2 = mv.compute_step(stub, DT)
		stub.position += step
		out.append(stub.position)
		if stub.position.y >= Playfield.Y_MAX + 8.0:
			break
	return out
