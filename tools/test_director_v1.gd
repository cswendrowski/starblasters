extends SceneTree

# Headless integration check for conductor v1 (streaming). Drives the REAL
# director with a single 12-enemy stream, cap = 3, and stub enemies that live
# 0.8s (long enough that the uncapped spawn rate would exceed the cap). Samples
# the live non-hazard count every frame and asserts:
#   - on-screen count NEVER exceeds the cap (density holds by construction),
#   - all 12 enemies eventually spawn (stream drains under the cap),
#   - level_cleared fires.
# Run: godot --headless --script res://tools/test_director_v1.gd

const RESULT := "res://tools/_director_v1_result.txt"
const CAP := 3
const TOTAL := 12

var _spawned: int = 0
var _cleared: bool = false
var _t: float = 0.0
var _started: bool = false
var _max_alive: int = 0
var _log: Array = []


func _make_stub_scene() -> PackedScene:
	var stub := GDScript.new()
	stub.source_code = "extends Area2D\n" \
		+ "signal died(value)\n" \
		+ "func start(pos):\n" \
		+ "\tposition = pos\n" \
		+ "\tawait get_tree().create_timer(0.8).timeout\n" \
		+ "\tqueue_free()\n"
	stub.reload()
	var node := Area2D.new()
	node.set_script(stub)
	var ps := PackedScene.new()
	ps.pack(node)
	node.free()
	return ps


func _alive_now() -> int:
	var n := 0
	for e in get_root().get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			n += 1
	return n


func _setup() -> void:
	var WaveDef := load("res://scripts/levels/wave_def.gd")
	var LevelDef := load("res://scripts/levels/level_def.gd")
	var w = WaveDef.new()
	w.enemy_scene = _make_stub_scene()
	w.count = TOTAL
	w.silent = true
	w.spawn_delay = 0.05
	w.spawn_interval = 0.05   # anti-burst floor (0.20) dominates
	w.formation = 0
	var lvl = LevelDef.new()
	lvl.waves = [w]

	var DirectorScript := load("res://scripts/levels/director.gd")
	var dir = DirectorScript.new()
	dir.max_concurrent = CAP
	var holder := Node.new()
	get_root().add_child(holder)
	holder.add_child(dir)
	dir.enemy_spawned.connect(func(_p, _b): _spawned += 1)
	dir.level_cleared.connect(func(): _cleared = true)
	dir.start_level(lvl)


func _process(delta: float) -> bool:
	if not _started:
		_setup()
		_started = true
		return false
	_t += delta
	_max_alive = max(_max_alive, _alive_now())
	if _cleared or _t > 20.0:
		if _max_alive > CAP:
			_log.append("FAIL max_alive=%d exceeded cap=%d" % [_max_alive, CAP])
		if _spawned != TOTAL:
			_log.append("FAIL spawned=%d expected %d" % [_spawned, TOTAL])
		if not _cleared:
			_log.append("FAIL level_cleared did not fire (t=%.1f)" % _t)
		if _log.is_empty():
			_log.append("DIRECTOR_V1 TEST: PASS (cap held at %d, spawned %d, cleared)" % [_max_alive, _spawned])
		else:
			_log.append("DIRECTOR_V1 TEST: FAIL")
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_log)))
			f.close()
		return true
	return false
