extends SceneTree

# EmitterComponent: emit payload scenes on a trigger. Tests the DEATH drop (the
# firecore/death-scatter pattern) — when the carrier dies, `count` payloads spawn at
# the scene root (surviving the carrier's free). Run:
#   godot --headless --script res://tools/test_emitter_component.gd

const RESULT := "res://tools/_emitter_result.txt"
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const Emitter := preload("res://scripts/enemies/components/emitter_component.gd")

var _e = null
var _frame := 0
var _phase := 0
var _hazards_before := 0
var _done := false


func _hazard_count() -> int:
	var n := 0
	for x in get_nodes_in_group("enemies"):
		if "is_hazard" in x and x.is_hazard:
			n += 1
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _phase == 0:
		var world := Node2D.new()
		root.add_child(world)
		var dart = load("res://scenes/enemies/core/enemy_core_s_dart.tscn").instantiate()
		var mv = StraightDown.new()
		dart.movement = mv
		var em = Emitter.new()
		em.payload = load("res://scenes/enemies/enemy_mine.tscn")
		em.trigger = Emitter.Trigger.DEATH
		em.count = 2
		em.chance = 1.0
		dart.components = [em]
		world.add_child(dart)
		dart.max_health = 1; dart.health = 1
		dart.start(Vector2(240, 60))
		_e = dart
		_phase = 1
		return false
	if _phase == 1:
		if _frame < 4:
			return false
		_hazards_before = _hazard_count()       # 0 (dart is not a hazard)
		_e.take_hit(99)                          # fatal -> explode -> on_death -> emit
		_phase = 2
		return false
	# phase 2: mines should now exist as hazards at the scene root
	var dropped: int = _hazard_count() - _hazards_before
	var lines: Array = []
	var fails := 0
	if dropped != 2:
		lines.append("FAIL expected 2 dropped mines, got %d (before=%d)" % [dropped, _hazards_before]); fails += 1
	lines.append("death-drop: before=%d dropped=%d" % [_hazards_before, dropped])
	lines.append("EMITTER COMPONENT: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	_done = true
	quit()
	return true
