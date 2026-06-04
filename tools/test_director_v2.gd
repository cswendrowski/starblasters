extends SceneTree

# Headless integration check for conductor v2 (lane spawn placement). Drives the
# REAL director with a 10-enemy TOP-formation stream and stub enemies that hold
# their spawn position, then verifies every spawn X lands on a Lanes lane center
# and the stream spreads across multiple lanes (alternate-anchor working).
# Run: godot --headless --script res://tools/test_director_v2.gd

const RESULT := "res://tools/_director_v2_result.txt"
const TOTAL := 10

var _spawned: int = 0
var _cleared: bool = false
var _t: float = 0.0
var _started: bool = false
var _lanes_seen: Dictionary = {}
var _off_center := false
var _log: Array = []


func _make_stub_scene() -> PackedScene:
	var stub := GDScript.new()
	stub.source_code = "extends Area2D\n" \
		+ "signal died(value)\n" \
		+ "func start(pos):\n" \
		+ "\tposition = pos\n" \
		+ "\tawait get_tree().create_timer(1.5).timeout\n" \
		+ "\tqueue_free()\n"
	stub.reload()
	var node := Area2D.new()
	node.set_script(stub)
	var ps := PackedScene.new()
	ps.pack(node)
	node.free()
	return ps


func _sample() -> void:
	for e in get_root().get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var ln: int = Lanes.nearest_lane(e.position.x)
		if absf(e.position.x - Lanes.lane_center(ln)) > 0.6:
			_off_center = true
		_lanes_seen[ln] = true


func _setup() -> void:
	var WaveDef := load("res://scripts/levels/wave_def.gd")
	var LevelDef := load("res://scripts/levels/level_def.gd")
	var w = WaveDef.new()
	w.enemy_scene = _make_stub_scene()
	w.count = TOTAL
	w.silent = true
	w.spawn_delay = 0.05
	w.spawn_interval = 0.05
	w.formation = 0          # TOP_LEFT_TO_RIGHT -> now lane-placed
	var lvl = LevelDef.new()
	lvl.waves = [w]

	var DirectorScript := load("res://scripts/levels/director.gd")
	var dir = DirectorScript.new()
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
	_sample()
	if _cleared or _t > 20.0:
		if _off_center:
			_log.append("FAIL a spawn was not on a lane center")
		if _lanes_seen.size() < 3:
			_log.append("FAIL only %d distinct lanes used (expected >=3)" % _lanes_seen.size())
		if _spawned != TOTAL:
			_log.append("FAIL spawned=%d expected %d" % [_spawned, TOTAL])
		if not _cleared:
			_log.append("FAIL level_cleared did not fire (t=%.1f)" % _t)
		if _log.is_empty():
			_log.append("DIRECTOR_V2 TEST: PASS (all on lane centers, %d lanes used, %d spawned)" % [_lanes_seen.size(), _spawned])
		else:
			_log.append("DIRECTOR_V2 TEST: FAIL")
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_log)))
			f.close()
		return true
	return false
