extends SceneTree

# Pattern-pass P1 verification for Skirmisher (advance_retreat) + Anchor (slow_advance).
# Skirmisher: eased advance (ease-in), reaches advance_y, retreats up, after `cycles`
#   it EXITS by accelerating UP and off (negative y, growing). No lateral drift.
# Anchor: slow STRAIGHT descent, no x drift, reaches the bottom (deep hold_y).
# Run: godot --headless --script res://tools/test_advance_anchor.gd

const RESULT := "res://tools/_advance_anchor_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _test_skirmisher() -> void:
	var e := Node2D.new()
	root.add_child(e)
	e.position = Vector2(240, 0)
	var m = Roster.make_movement({"movement": "advance_retreat"})
	m.on_start(e)
	var start_x: float = e.position.x

	# ease-in: first advance step slower than cruise.
	var first: Vector2 = m.compute_step(e, DT); e.position += first
	if first.y >= m.advance_speed * DT:
		_fail("skirmisher: no ease-in (%.2f >= cruise %.2f)" % [first.y, m.advance_speed * DT])

	var saw_advance := false
	var saw_retreat := false
	var max_x_dev := 0.0
	var t := 0.0
	# run until EXIT or timeout. Phase enum: ADVANCE0 HOLD1 RETREAT2 PREP3 EXIT4.
	while t < 12.0 and m._phase != 4:  # EXIT
		var s: Vector2 = m.compute_step(e, DT)
		e.position += s
		t += DT
		if m._phase == 0 and s.y > 0.0: saw_advance = true   # real advance, not jiggle
		if m._phase == 2 and s.y < 0.0: saw_retreat = true   # real retreat, not jiggle
		max_x_dev = maxf(max_x_dev, absf(e.position.x - start_x))

	if not saw_advance: _fail("skirmisher: never advanced")
	if not saw_retreat: _fail("skirmisher: never retreated")
	# Hold/prep jiggle adds small lateral motion by design; only flag gross drift.
	if max_x_dev > 9.0: _fail("skirmisher: x drift too large (%.3f)" % max_x_dev)
	if m._phase != 4:
		_fail("skirmisher: never reached EXIT")
	else:
		# EXIT: must move UP and accelerate.
		var a: Vector2 = m.compute_step(e, DT); e.position += a
		for i in 15:
			e.position += m.compute_step(e, DT)
		var b: Vector2 = m.compute_step(e, DT); e.position += b
		if a.y >= 0.0: _fail("skirmisher: exit not upward (%.2f)" % a.y)
		if b.y >= a.y: _fail("skirmisher: exit not accelerating up (%.2f -> %.2f)" % [a.y, b.y])
		_lines.append("skirmisher ok: exit dy %.2f -> %.2f, max_x_dev=%.3f" % [a.y, b.y, max_x_dev])
	e.queue_free()


func _test_anchor() -> void:
	var e := Node2D.new()
	root.add_child(e)
	e.position = Vector2(200, 0)
	var m = Roster.make_movement({"movement": "slow_advance"})
	m.on_start(e)
	var start_x: float = e.position.x
	var max_x_dev := 0.0
	var t := 0.0
	var prev_y := e.position.y
	var always_down := true
	while t < 8.0 and e.position.y < 270.0:
		e.position += m.compute_step(e, DT)
		t += DT
		max_x_dev = maxf(max_x_dev, absf(e.position.x - start_x))
		if e.position.y < prev_y: always_down = false
		prev_y = e.position.y
	if e.position.y < 270.0:
		_fail("anchor: never reached bottom (y=%.1f after %.1fs)" % [e.position.y, t])
	if max_x_dev > 0.01:
		_fail("anchor: drifted in x (%.3f) — should be a straight slow Diver" % max_x_dev)
	if not always_down:
		_fail("anchor: did not descend monotonically")
	_lines.append("anchor ok: straight descent, max_x_dev=%.3f, reached y=%.0f in %.1fs" % [max_x_dev, e.position.y, t])
	e.queue_free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_test_skirmisher()
	_test_anchor()
	_lines.append("ADVANCE/ANCHOR: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	_done = true
	quit()
	return true
