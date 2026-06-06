extends SceneTree

# P2c.2 lane-aware lane CHANGERS (lane_path HOOK=Shifter, STEP=Drifter). Verifies:
#   Shifter commits to the adjacent lane when it's free; HOLDS its lane when the
#     target is blocked, then commits once the target clears.
#   Drifter hops when the target lane is free; HOLDS when blocked, then hops once
#     clear.
# down_speed is 0 in these cases so a static occupant keeps blocking (we're testing
# the lateral commit logic, not descent). Run:
#   godot --headless --script res://tools/test_lane_changers.gd

const RESULT := "res://tools/_lane_changers_result.txt"
const LanePath := preload("res://scripts/enemies/patterns/lane_path.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _mover(lane: int, y: float) -> Node2D:
	var n := Node2D.new()
	n.position = Vector2(Lanes.lane_center(lane), y)
	root.add_child(n)
	return n


func _occupant(lane: int, y: float) -> Node2D:
	var n := Node2D.new()
	n.position = Vector2(Lanes.lane_center(lane), y)
	root.add_child(n)
	n.add_to_group("enemies")
	return n


func _tick(mover: Node2D, p, frames: int) -> void:
	for i in frames:
		mover.position += p.compute_step(mover, DT)


func _lane_of(n: Node2D) -> int:
	return Lanes.nearest_lane(n.position.x)


func _test_shifter() -> void:
	# free target -> commits to lane 3
	var m := _mover(2, 60.0)
	var p = LanePath.new()
	p.shape = LanePath.Shape.HOOK
	p.shift_lanes = 1
	p.shift_delay = 0.2
	p.shift_duration = 0.5
	p.down_speed = 0.0
	p.on_start(m)
	_tick(m, p, 90)  # 1.5s
	if _lane_of(m) != 3:
		_fail("shifter(free) did not commit to lane 3 (lane=%d)" % _lane_of(m))
	m.queue_free()

	# blocked target -> holds lane 2, then commits when cleared
	var m2 := _mover(2, 60.0)
	var occ := _occupant(3, 60.0)
	var p2 = LanePath.new()
	p2.shape = LanePath.Shape.HOOK
	p2.shift_lanes = 1
	p2.shift_delay = 0.2
	p2.shift_duration = 0.5
	p2.down_speed = 0.0
	p2.on_start(m2)
	_tick(m2, p2, 90)
	if _lane_of(m2) != 2:
		_fail("shifter(blocked) should hold lane 2 (lane=%d)" % _lane_of(m2))
	occ.position.y = 1000.0   # clear lane 3 (out of the Y window)
	_tick(m2, p2, 90)
	if _lane_of(m2) != 3:
		_fail("shifter(cleared) should now commit to lane 3 (lane=%d)" % _lane_of(m2))
	_lines.append("shifter ok: free->3, blocked->held->3")
	m2.queue_free(); occ.queue_free()


func _test_drifter() -> void:
	# free target -> hops off lane 2 (step_dir is +1 from lane 2)
	var m := _mover(2, 60.0)
	var p = LanePath.new()
	p.shape = LanePath.Shape.STEP
	p.hold_time = 0.5
	p.step_time = 0.2
	p.step_lanes = 1
	p.down_speed = 0.0
	p.on_start(m)
	_tick(m, p, 90)
	if _lane_of(m) == 2:
		_fail("drifter(free) never hopped off lane 2")
	m.queue_free()

	# blocked target (lane 3) -> holds lane 2, then hops when cleared
	var m2 := _mover(2, 60.0)
	var occ := _occupant(3, 60.0)
	var p2 = LanePath.new()
	p2.shape = LanePath.Shape.STEP
	p2.hold_time = 0.5
	p2.step_time = 0.2
	p2.step_lanes = 1
	p2.down_speed = 0.0
	p2.on_start(m2)
	_tick(m2, p2, 90)
	if _lane_of(m2) != 2:
		_fail("drifter(blocked) should hold lane 2 (lane=%d)" % _lane_of(m2))
	occ.position.y = 1000.0
	_tick(m2, p2, 90)
	if _lane_of(m2) == 2:
		_fail("drifter(cleared) should have hopped off lane 2")
	_lines.append("drifter ok: free->hop, blocked->held->hop")
	m2.queue_free(); occ.queue_free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_test_shifter()
	_test_drifter()
	_lines.append("LANE CHANGERS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
