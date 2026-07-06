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

	# Iterate the BAKED library (DATA) directly and build from the baked def — tests 1–4 validate the
	# committed geometry regardless of any user-override JSON present on the dev machine (the override
	# shadowing itself is covered by _test_shadowing). Using build_from_def bypasses the resolve-time
	# override lookup that build(name) performs.
	for name in AuthoredPathLibrary.DATA.keys():
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
		var mv := AuthoredPathLibrary.build_from_def(def)
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

	# --- (5) snap math round-trips ---------------------------------------------
	fails += _test_snap_math(lines)

	# --- (6) user-override shadowing -------------------------------------------
	fails += _test_shadowing(lines)

	lines.append("AUTHORED PATH TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	print("\n".join(PackedStringArray(lines)))
	quit()


const OVERRIDE_PATH := "user://tuners/enemy_paths.json"


# (5) Lane/row snap round-trips: an on-grid value survives snap unchanged; an off-grid value snaps to
# the nearest grid coordinate; half-lane snap keeps x.5; row snap lands on a ROW_GRID_BP multiple.
func _test_snap_math(lines: Array) -> int:
	var fails: int = 0
	# Whole-lane snap.
	if AuthoredPath.snap_lane_x(2.0, false) != 2.0:
		lines.append("FAIL snap: on-grid lane 2.0 moved to %.3f" % AuthoredPath.snap_lane_x(2.0, false)); fails += 1
	if AuthoredPath.snap_lane_x(2.2, false) != 2.0:
		lines.append("FAIL snap: 2.2 → %.3f (expect 2.0)" % AuthoredPath.snap_lane_x(2.2, false)); fails += 1
	if AuthoredPath.snap_lane_x(2.6, false) != 3.0:
		lines.append("FAIL snap: 2.6 → %.3f (expect 3.0)" % AuthoredPath.snap_lane_x(2.6, false)); fails += 1
	# Half-lane snap keeps x.5.
	if AuthoredPath.snap_lane_x(2.4, true) != 2.5:
		lines.append("FAIL snap: half 2.4 → %.3f (expect 2.5)" % AuthoredPath.snap_lane_x(2.4, true)); fails += 1
	# Row snap: multiples of ROW_GRID_BP, clamped 0..1.
	var g: float = AuthoredPath.ROW_GRID_BP
	if absf(AuthoredPath.snap_band_y(g) - g) > 0.0001:
		lines.append("FAIL snap: on-grid row moved"); fails += 1
	var sy: float = AuthoredPath.snap_band_y(g * 2.2)
	if absf(sy - g * 2.0) > 0.0001:
		lines.append("FAIL snap: row %.4f → %.4f (expect %.4f)" % [g * 2.2, sy, g * 2.0]); fails += 1
	if AuthoredPath.snap_band_y(1.5) > 1.0 or AuthoredPath.snap_band_y(-0.5) < 0.0:
		lines.append("FAIL snap: band-y not clamped to [0,1]"); fails += 1
	lines.append("snap: lane/row round-trips OK (row_grid_bp=%.4f count=%d)" % [g, AuthoredPath.row_grid_count()])
	return fails


# (6) User-override shadowing: a user-JSON entry with a baked name changes build() output; with the
# file absent, build() returns the baked DATA. State is restored (original file contents / absence).
func _test_shadowing(lines: Array) -> int:
	var fails: int = 0
	var name: String = "s_weave"   # a known baked path
	# Preserve any existing override file so the test is non-destructive.
	var had_file: bool = FileAccess.file_exists(OVERRIDE_PATH)
	var saved: String = ""
	if had_file:
		var rf := FileAccess.open(OVERRIDE_PATH, FileAccess.READ)
		if rf != null:
			saved = rf.get_as_text()
			rf.close()

	# Baseline: absent-file (or original) must build the BAKED speed_scale.
	AuthoredPathLibrary.reload_overrides()
	var baked_scale: float = float(AuthoredPathLibrary.DATA[name].get("speed_scale", 1.0))
	var m0 = AuthoredPathLibrary.build(name)
	if m0 == null or absf(m0.speed_scale - baked_scale) > 0.0001:
		lines.append("FAIL shadow: baseline build did not match baked speed_scale"); fails += 1

	# Write an override with a DISTINCT speed_scale under the same name.
	var override_scale: float = baked_scale + 0.5
	var ov := (AuthoredPathLibrary.DATA[name] as Dictionary).duplicate(true)
	ov["speed_scale"] = override_scale
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var wf := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
	wf.store_string(JSON.stringify([ov], "\t"))
	wf.close()
	AuthoredPathLibrary.reload_overrides()
	var m1 = AuthoredPathLibrary.build(name)
	if m1 == null or absf(m1.speed_scale - override_scale) > 0.0001:
		lines.append("FAIL shadow: override did not shadow baked (got %.3f expect %.3f)" % [
			-1.0 if m1 == null else m1.speed_scale, override_scale]); fails += 1

	# Remove the file → build must fall back to baked again.
	DirAccess.remove_absolute(OVERRIDE_PATH)
	AuthoredPathLibrary.reload_overrides()
	var m2 = AuthoredPathLibrary.build(name)
	if m2 == null or absf(m2.speed_scale - baked_scale) > 0.0001:
		lines.append("FAIL shadow: absent-file build did not fall back to baked"); fails += 1

	# Restore original state.
	if had_file:
		var rwf := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
		rwf.store_string(saved)
		rwf.close()
	AuthoredPathLibrary.reload_overrides()
	if fails == 0:
		lines.append("shadow: user-JSON override precedence OK (baked=%.2f override=%.2f)" % [baked_scale, override_scale])
	return fails


# Per-frame arc-length advance of the pattern's internal cursor over a full traversal, EXCLUDING the
# final frame (which is a partial step + straight-line overrun past the last waypoint).
func _arc_advances(name: String) -> Array:
	var mv := AuthoredPathLibrary.build_from_def(AuthoredPathLibrary.DATA[name])
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
	var mv := AuthoredPathLibrary.build_from_def(AuthoredPathLibrary.DATA[name])
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
