extends SceneTree

# ShieldComponent: absorbs hits while charged (hull untouched), passes damage through
# when depleted, regenerates a charge after regen_interval. Exercised on a real spawned
# enemy via the M6a.1 framework. Run: godot --headless --script res://tools/test_shield_component.gd

const RESULT := "res://tools/_shield_result.txt"
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const ShieldComp := preload("res://scripts/enemies/components/shield_component.gd")

var _e = null
var _sh = null
var _frame := 0
var _phase := 0
var _elapsed := 0.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(msg: String) -> void:
	_lines.append("FAIL " + msg); _fails += 1


func _process(dt: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _phase == 0:
		var world := Node2D.new()
		root.add_child(world)
		var dart = load("res://scenes/enemies/enemy_dart.tscn").instantiate()
		var mv = StraightDown.new(); mv.speed = 0.0
		dart.movement = mv
		var sc = ShieldComp.new()
		sc.capacity = 2
		sc.regen_interval = 0.4
		dart.components = [sc]
		world.add_child(dart)
		dart.max_health = 5; dart.health = 5
		dart.start(Vector2(240, 60))
		_e = dart
		_phase = 1
		return false
	if _phase == 1:
		if _frame < 6:                       # let deferred on_start fire
			return false
		_sh = _e._components[0]
		if _sh._charges != 2:
			_fail("on_start didn't charge shield (%d)" % _sh._charges)
		_e.take_hit(1)                       # absorb 1
		_e.take_hit(1)                       # absorb 2 -> depleted
		if _e.health != 5:
			_fail("shield didn't absorb (health %d != 5)" % _e.health)
		if _sh._charges != 0:
			_fail("charges %d != 0 after 2 hits" % _sh._charges)
		_e.take_hit(1)                       # depleted -> hits hull
		if _e.health != 4:
			_fail("depleted shield didn't pass damage (health %d != 4)" % _e.health)
		_phase = 2
		_elapsed = 0.0
		return false
	# phase 2: wait for regen, then confirm it absorbs again
	_elapsed += dt
	if _elapsed < 0.6:
		return false
	if _sh._charges < 1:
		_fail("shield did not regen (charges %d)" % _sh._charges)
	_e.take_hit(1)
	if _e.health != 4:
		_fail("regenerated shield didn't absorb (health %d != 4)" % _e.health)
	_lines.append("absorb+deplete+regen ok ; final health=%d charges=%d" % [_e.health, _sh._charges])
	_lines.append("SHIELD COMPONENT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	_done = true
	quit()
	return true
