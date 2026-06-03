extends SceneTree

# Headless unit check for lane_path.gd (M1). Drives compute_step directly on a
# bare Node2D stub (the pattern only reads enemy.position). Verifies HOOK lands
# the right lane delta, MIRROR reflects it, STRAIGHT holds the lane, and descent
# accumulates. Run: godot --headless -s tools/test_lane_path.gd

const LanePath = preload("res://scripts/enemies/patterns/lane_path.gd")
const DT := 1.0 / 60.0
const RESULT_PATH := "res://tools/_lane_path_result.txt"

var _log: Array = []


func _say(s: String) -> void:
	_log.append(s)


func _tick(p, e, frames: int) -> void:
	for _i in frames:
		e.position += p.compute_step(e, DT)


func _init() -> void:
	var fails := 0

	# HOOK: +2 lanes from the center lane over 0.5s; after 1s fully hooked.
	var p = LanePath.new()
	p.shape = LanePath.Shape.HOOK
	p.shift_lanes = 2
	p.shift_duration = 0.5
	p.down_speed = 120.0
	var e := Node2D.new()
	var start_x: float = Lanes.lane_center(3)
	e.position = Vector2(start_x, 0.0)
	p.on_start(e)
	_tick(p, e, 60)
	var dx: float = e.position.x - start_x
	var expected: float = 2.0 * Lanes.PITCH
	if absf(dx - expected) > 2.0:
		_say("FAIL hook dx=%.2f expected~%.2f" % [dx, expected]); fails += 1
	if e.position.y < 100.0:
		_say("FAIL hook descent y=%.2f (expected ~120)" % e.position.y); fails += 1
	if absf(e.position.x - Lanes.lane_center(5)) > 2.0:
		_say("FAIL hook did not land lane 5 x=%.2f" % e.position.x); fails += 1
	e.free()

	# MIRROR: same hook reflected -> goes LEFT to lane 1.
	var pm = LanePath.new()
	pm.shape = LanePath.Shape.HOOK
	pm.shift_lanes = 2
	pm.shift_duration = 0.5
	pm.mirrored = true
	pm.down_speed = 120.0
	var em := Node2D.new()
	em.position = Vector2(start_x, 0.0)
	pm.on_start(em)
	_tick(pm, em, 60)
	if absf(em.position.x - Lanes.lane_center(1)) > 2.0:
		_say("FAIL mirror did not land lane 1 x=%.2f" % em.position.x); fails += 1
	em.free()

	# STRAIGHT: holds the spawn lane, only descends.
	var ps = LanePath.new()
	ps.shape = LanePath.Shape.STRAIGHT
	ps.down_speed = 120.0
	var es := Node2D.new()
	es.position = Vector2(Lanes.lane_center(2), 0.0)
	ps.on_start(es)
	_tick(ps, es, 60)
	if absf(es.position.x - Lanes.lane_center(2)) > 0.5:
		_say("FAIL straight drifted x=%.2f" % es.position.x); fails += 1
	if es.position.y < 100.0:
		_say("FAIL straight descent y=%.2f" % es.position.y); fails += 1
	es.free()

	if fails == 0:
		_say("LANE_PATH TEST: PASS")
	else:
		_say("LANE_PATH TEST: %d FAIL(s)" % fails)
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_log)))
		f.close()
	quit()
