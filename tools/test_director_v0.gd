extends SceneTree

# Headless integration check for conductor v0 (the faithful port). Drives the
# REAL director through the new pipeline (LevelData -> ScoreAdapter -> CombatScore
# -> flattened walk) with a tiny silent 3-enemy level and a runtime stub enemy,
# and asserts: 3 enemies spawn (enemy_spawned fires 3x) and level_cleared fires
# once they free. Confirms the score pipeline drives spawning + clear exactly.
# Run: godot --headless --script res://tools/test_director_v0.gd

const RESULT := "res://tools/_director_v0_result.txt"

var _spawned: int = 0
var _cleared: bool = false
var _t: float = 0.0
var _started: bool = false
var _log: Array = []


func _make_stub_scene() -> PackedScene:
	var stub := GDScript.new()
	stub.source_code = "extends Area2D\n" \
		+ "signal died(value)\n" \
		+ "func start(pos):\n" \
		+ "\tposition = pos\n" \
		+ "\tawait get_tree().create_timer(0.25).timeout\n" \
		+ "\tqueue_free()\n"
	stub.reload()
	var node := Area2D.new()
	node.set_script(stub)
	var ps := PackedScene.new()
	ps.pack(node)
	node.free()
	return ps


func _setup() -> void:
	var WaveDef := load("res://scripts/levels/wave_def.gd")
	var LevelDef := load("res://scripts/levels/level_def.gd")
	var w = WaveDef.new()
	w.enemy_scene = _make_stub_scene()
	w.count = 3
	w.silent = true          # skip the banner wait -> fast
	w.spawn_delay = 0.05
	w.spawn_interval = 0.05
	w.formation = 0
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
	_started = true


func _process(delta: float) -> bool:
	# Defer setup to the first frame: nodes added during _initialize() aren't
	# tree-ready (get_tree() returns null), which breaks the director's timers.
	if not _started:
		_setup()
		_started = true
		return false
	_t += delta
	if _cleared or _t > 6.0:
		if _spawned != 3:
			_log.append("FAIL spawned=%d expected 3" % _spawned)
		if not _cleared:
			_log.append("FAIL level_cleared did not fire (t=%.1f)" % _t)
		if _log.is_empty():
			_log.append("DIRECTOR_V0 TEST: PASS (spawned=3, cleared)")
		else:
			_log.append("DIRECTOR_V0 TEST: FAIL")
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_log)))
			f.close()
		return true
	return false
