extends SceneTree

# Holder (loiter.gd) pattern-pass verification. Confirms, for each variant:
#   - ease-IN: first-frame step is slower than cruise (no hard pop-in)
#   - reaches the hold band at the variant's hover_y (low/mid/high)
#   - HOLD jiggles (y oscillates around hover_y; not frozen at exactly hover_y)
#   - after loiter_time, EXITS downward and accelerates
# Run: godot --headless --script res://tools/test_loiter_holder.gd

const RESULT := "res://tools/_loiter_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


# Chassis-aware stub: loiter reads hold DEPTH from enemy.depth_bp and descent SPEED from
# enemy.move_speed via the movement_pattern accessors, which require the PROPERTY to exist (a bare
# Node2D gets the medium default). depth_bp drives hold height; move_speed 0 → the 180 medium default.
class Dummy extends Node2D:
	var move_speed: float = 0.0
	var depth_bp: float = -1.0


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _run_variant(key: String, depth_bp: float, expect_y: float) -> void:
	var e := Dummy.new()
	e.depth_bp = depth_bp   # hold depth is chassis-owned now (was the loiter_high/mid/low key)
	root.add_child(e)
	# Spawn at y=12 — matches the visualizer "Spawn row" + a short-entry case so
	# the high variant (hold y=50, only 38px down) exercises the entry floor.
	e.position = Vector2(240, 12)
	var m = Roster.make_movement({"movement": "loiter"})
	m.on_start(e)

	# ease-in: first compute_step should be slower than cruise (enter_speed * dt).
	var first: Vector2 = m.compute_step(e, DT)
	e.position += first
	var cruise_step: float = 180.0 * DT
	if first.y >= cruise_step:
		_fail("%s: no ease-in (first step %.2f >= cruise %.2f)" % [key, first.y, cruise_step])

	# tick until it reaches the hold band (or give up after 4s).
	var t := 0.0
	var reached := false
	while t < 4.0:
		e.position += m.compute_step(e, DT)
		t += DT
		if absf(e.position.y - expect_y) <= 1.5 and m._phase == 1:  # LOITERING
			reached = true
			break
	if not reached:
		_fail("%s: never reached hold band y=%.0f (ended y=%.1f phase=%d)" % [key, expect_y, e.position.y, m._phase])
		e.queue_free()
		return

	# HOLD: sample y over ~1s; it must vary (jiggle) but stay near hover_y.
	var ymin := e.position.y
	var ymax := e.position.y
	for i in 60:
		e.position += m.compute_step(e, DT)
		ymin = minf(ymin, e.position.y)
		ymax = maxf(ymax, e.position.y)
	var spread: float = ymax - ymin
	if spread < 0.5:
		_fail("%s: hold is frozen (y spread %.2f)" % [key, spread])
	if spread > 14.0:
		_fail("%s: hold jiggle too wild (y spread %.2f)" % [key, spread])
	# Per-instance random phase gives a small DC bias (<= jiggle_amp_y), so the
	# hold center varies a few px around hover_y by design — allow it.
	if absf((ymin + ymax) * 0.5 - expect_y) > 5.0:
		_fail("%s: jiggle not centered near hover_y (mid %.1f vs %.0f)" % [key, (ymin + ymax) * 0.5, expect_y])

	# EXIT: after loiter_time, must move downward and accelerate.
	var tt := 0.0
	while tt < 4.0 and m._phase != 2:  # EXITING
		e.position += m.compute_step(e, DT)
		tt += DT
	if m._phase != 2:
		_fail("%s: never exited" % key)
	else:
		var s1: Vector2 = m.compute_step(e, DT); e.position += s1
		for j in 20:
			e.position += m.compute_step(e, DT)
		var s2: Vector2 = m.compute_step(e, DT); e.position += s2
		if s1.y <= 0.0:
			_fail("%s: exit not downward (%.2f)" % [key, s1.y])
		if s2.y <= s1.y:
			_fail("%s: exit not accelerating (%.2f -> %.2f)" % [key, s1.y, s2.y])

	_lines.append("%s ok: hold~y=%.0f spread=%.2f" % [key, (ymin + ymax) * 0.5, spread])
	e.queue_free()


func _test_row_desync() -> void:
	# Spawn a ROW of Holders, tick them in lockstep into the hold, then confirm
	# their hold positions differ (randomized jiggle, not lockstep). Roman 06-06.
	var es: Array = []
	for i in 6:
		var e := Dummy.new()
		e.depth_bp = Zones.band_progress(90.0)
		root.add_child(e)
		e.position = Vector2(240, 0)
		var m = Roster.make_movement({"movement": "loiter"})
		m.on_start(e)
		es.append({"e": e, "m": m})
	# tick everyone identically into the hold (entry ~0.5s; loiter_time 3s) and
	# sample mid-hold at frame ~120 (2s) — BEFORE they exit (after which they'd
	# descend identically again).
	for f in 120:
		for d in es:
			d["e"].position += d["m"].compute_step(d["e"], DT)
	# Sample positions; at least some must differ in x OR y.
	var ys: Array = []
	var xs: Array = []
	for d in es:
		ys.append(d["e"].position.y)
		xs.append(d["e"].position.x)
	var y_spread: float = ys.max() - ys.min()
	var x_spread: float = xs.max() - xs.min()
	if y_spread < 0.5 and x_spread < 0.5:
		_fail("row desync: all Holders identical (y_spread %.3f x_spread %.3f)" % [y_spread, x_spread])
	else:
		_lines.append("row desync ok: y_spread=%.2f x_spread=%.2f across 6" % [y_spread, x_spread])
	for d in es:
		d["e"].queue_free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_run_variant("high", Zones.band_progress(50.0), 50.0)
	_run_variant("mid", Zones.band_progress(90.0), 90.0)
	_run_variant("low", Zones.band_progress(130.0), 130.0)
	_test_row_desync()
	_lines.append("LOITER HOLDER: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	_done = true
	quit()
	return true
