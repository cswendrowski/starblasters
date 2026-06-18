extends SceneTree

# M6a.1 component framework: enemy_base dupes components[] per-instance and fans out
# on_start (deferred, after positioning) / on_process (enemy_core tick) / on_hit
# (damage routing) / on_death; health_changed fires on hull change. Spawns a real
# enemy_core enemy (dart) with a probe component and exercises the full lifecycle.
# Run: godot --headless --script res://tools/test_components_framework.gd

const RESULT := "res://tools/_components_fw_result.txt"
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const Probe := preload("res://tools/test_component_probe.gd")

var _enemy = null
var _comp = null
var _hc_fired := false
var _frame := 0
var _phase := 0
var _done := false
var _lines: Array = []
var _fails := 0


func _process(_dt: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _phase == 0:
		var world := Node2D.new()
		root.add_child(world)
		var dart = load("res://scenes/enemies/factions/privateer/enemy_dart.tscn").instantiate()
		var mv = StraightDown.new()
		mv.speed = 60.0
		dart.movement = mv
		dart.components = [Probe.new()]
		world.add_child(dart)            # _ready dupes the component
		dart.max_health = 5
		dart.health = 5
		dart.health_changed.connect(func(_c, _m): _hc_fired = true)
		dart.start(Vector2(240, 60))
		_enemy = dart
		_phase = 1
		return false
	if _phase == 1:
		if _frame < 8:                   # let the deferred on_start + a few process ticks run
			return false
		_comp = _enemy._components[0]
		if not _comp.started:
			_lines.append("FAIL on_start never fired"); _fails += 1
		if _comp.processed <= 0:
			_lines.append("FAIL on_process never ticked"); _fails += 1
		_enemy.take_hit(1)               # non-fatal
		if _comp.last_hit != 1:
			_lines.append("FAIL on_hit not routed (last_hit=%d)" % _comp.last_hit); _fails += 1
		if not _hc_fired:
			_lines.append("FAIL health_changed not emitted"); _fails += 1
		if _enemy.health != 4:
			_lines.append("FAIL health %d != 4 after hit" % _enemy.health); _fails += 1
		_enemy.take_hit(10)              # fatal -> explode -> on_death (sync, before the free await)
		if not _comp.died:
			_lines.append("FAIL on_death not fired"); _fails += 1
		_lines.append("started=%s processed=%d last_hit=%d hc=%s died=%s" % [
			str(_comp.started), _comp.processed, _comp.last_hit, str(_hc_fired), str(_comp.died)])
		_lines.append("COMPONENTS FRAMEWORK: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_lines)))
			f.close()
		_done = true
		quit()
		return true
	return false
