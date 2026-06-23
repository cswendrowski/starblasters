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


# Chassis-aware mover: lane_path reads descent SPEED from enemy.move_speed (down_speed is vestigial
# post-2026-06-19), and the accessor needs the PROPERTY to exist (a bare Node2D gets 180). Setting
# move_speed ~1 keeps the lateral-commit movers near a fixed-Y occupant; the zone test sets the
# real cross speed. (Occupants stay bare Node2D — they're positioned by hand, not by a pattern.)
class Dummy extends Node2D:
	var move_speed: float = 1.0


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _mover(lane: int, y: float, ms: float = 1.0) -> Node2D:
	var n := Dummy.new()
	n.move_speed = ms
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
	p.shift_duration = 0.5
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
	p2.shift_duration = 0.5
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


func _tick_to_y(m: Node2D, p, target_y: float, occ: Node2D = null) -> void:
	var guard := 0
	while m.position.y < target_y and guard < 4000:
		m.position += p.compute_step(m, DT)
		if occ != null:
			occ.position.y = m.position.y   # occupant rides alongside (stays blocking)
		guard += 1


func _test_drifter_zone() -> void:
	# Zone-timed Drifter (HOOK + zone_timed): holds the spawn lane through the entry
	# band, slides across the fire zone, lands in the adjacent lane by the band bottom.
	var m := _mover(2, 0.0, 120.0)
	var p = LanePath.new()
	p.shape = LanePath.Shape.HOOK
	p.zone_timed = true
	p.shift_lanes = 1
	p.on_start(m)
	_tick_to_y(m, p, 30.0)   # still in the entry band (Zones.ENTRY_END = 40)
	if _lane_of(m) != 2:
		_fail("drifter(zone) should hold lane 2 in the entry band (lane=%d)" % _lane_of(m))
	_tick_to_y(m, p, 200.0)  # past the fire-zone bottom (Zones.DEPARTURE_START = 195)
	if _lane_of(m) != 3:
		_fail("drifter(zone) should be in lane 3 by the fire-zone exit (lane=%d)" % _lane_of(m))

	# blocked the whole way (occupant rides alongside in lane 3) -> never slides.
	var m2 := _mover(2, 0.0, 120.0)
	var occ := _occupant(3, 0.0)
	var p2 = LanePath.new()
	p2.shape = LanePath.Shape.HOOK
	p2.zone_timed = true
	p2.shift_lanes = 1
	p2.on_start(m2)
	_tick_to_y(m2, p2, 200.0, occ)
	if _lane_of(m2) != 2:
		_fail("drifter(zone, blocked) should hold lane 2 (lane=%d)" % _lane_of(m2))
	_lines.append("drifter(zone) ok: held entry -> lane3 by exit; blocked -> held")
	m.queue_free(); m2.queue_free(); occ.queue_free()


func _test_stepper() -> void:
	# free target -> hops off lane 2 (step_dir is +1 from lane 2)
	var m := _mover(2, 60.0)
	var p = LanePath.new()
	p.shape = LanePath.Shape.STEP
	p.hold_time = 0.5
	p.step_time = 0.2
	p.step_lanes = 1
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
	p2.on_start(m2)
	_tick(m2, p2, 90)
	if _lane_of(m2) != 2:
		_fail("drifter(blocked) should hold lane 2 (lane=%d)" % _lane_of(m2))
	occ.position.y = 1000.0
	_tick(m2, p2, 90)
	if _lane_of(m2) == 2:
		_fail("drifter(cleared) should have hopped off lane 2")
	_lines.append("stepper(STEP) ok: free->hop, blocked->held->hop")
	m2.queue_free(); occ.queue_free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_test_shifter()
	_test_drifter_zone()
	_test_stepper()
	_lines.append("LANE CHANGERS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
