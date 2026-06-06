extends SceneTree

# P2d coordinated row step (synced STEP in lane_path). Verifies:
#   - _fold_offset is the expected reflected-walk sequence (closed form).
#   - two members at different anchor lanes, fed identical synced params + clock,
#     produce the SAME anchor-relative offset every frame (unison) and both stay on
#     the board, and the offset actually oscillates (the row really steps).
# Run: godot --headless --script res://tools/test_step_wall.gd

const RESULT := "res://tools/_step_wall_result.txt"
const LanePath := preload("res://scripts/enemies/patterns/lane_path.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _make(lane: int, lo: int, hi: int) -> Dictionary:
	var n := Node2D.new()
	n.position = Vector2(Lanes.lane_center(lane), 60.0)
	root.add_child(n)
	var p = LanePath.new()
	p.shape = LanePath.Shape.STEP
	p.step_synced = true
	p.step_offset_lo = lo
	p.step_offset_hi = hi
	p.step_start_dir = 1
	p.hold_time = 0.6
	p.step_time = 0.3
	p.down_speed = 0.0
	p.on_start(n)
	return {"n": n, "p": p, "anchor": lane}


func _offset_of(rec: Dictionary) -> float:
	return (rec["n"].position.x - Lanes.lane_center(rec["anchor"])) / Lanes.PITCH


func _test_fold() -> void:
	# lo=-1,hi=1,dir=1 -> 0,1,0,-1,0,1,0,-1
	var p = LanePath.new()
	p.step_offset_lo = -1; p.step_offset_hi = 1; p.step_start_dir = 1
	var want := [0, 1, 0, -1, 0, 1, 0, -1]
	for i in want.size():
		if p._fold_offset(i) != want[i]:
			_fail("fold[-1,1](%d)=%d want %d" % [i, p._fold_offset(i), want[i]]); break
	# lo=0,hi=1 -> 0,1,0,1
	p.step_offset_lo = 0; p.step_offset_hi = 1
	var want2 := [0, 1, 0, 1, 0]
	for i in want2.size():
		if p._fold_offset(i) != want2[i]:
			_fail("fold[0,1](%d)=%d want %d" % [i, p._fold_offset(i), want2[i]]); break


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	_test_fold()

	# Row members at lanes 1 and 4 -> lo=-min=-1, hi=COUNT-1-max=2.
	var lo := -1
	var hi := Lanes.COUNT - 1 - 4
	var a := _make(1, lo, hi)
	var b := _make(4, lo, hi)

	var omin := 0.0
	var omax := 0.0
	var unison_ok := true
	for f in 240:  # 4s
		a["n"].position += a["p"].compute_step(a["n"], DT)
		b["n"].position += b["p"].compute_step(b["n"], DT)
		var oa := _offset_of(a)
		var ob := _offset_of(b)
		if not is_equal_approx(oa, ob):
			unison_ok = false
		omin = minf(omin, oa); omax = maxf(omax, oa)
		# on-board for both
		var la := Lanes.nearest_lane(a["n"].position.x)
		var lb := Lanes.nearest_lane(b["n"].position.x)
		if la < 0 or la > Lanes.COUNT - 1 or lb < 0 or lb > Lanes.COUNT - 1:
			_fail("a member left the board (la=%d lb=%d)" % [la, lb]); break

	if not unison_ok:
		_fail("members did not step in unison (offsets diverged)")
	if (omax - omin) < 0.9:
		_fail("row never stepped (offset range %.2f)" % (omax - omin))

	_lines.append("fold ok ; unison=%s ; offset range %.2f..%.2f" % [str(unison_ok), omin, omax])
	_lines.append("STEP WALL: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var fh := FileAccess.open(RESULT, FileAccess.WRITE)
	if fh != null:
		fh.store_string("\n".join(PackedStringArray(_lines)))
		fh.close()
	quit()
	return true
