extends SceneTree

# Headless integration check for conductor v3 (phrase-native dispatch). Builds a
# hand-authored CombatScore (bypassing the adapter) with one wave of:
#   FORMATION(4) -> BREATHER(0.5s) -> FILLER(budget 5)
# and drives the REAL director via start_score, verifying:
#   - exactly 9 enemies spawn (4 formation + 5 filler),
#   - the breather inserts a real gap between the formation and the filler,
#   - level_cleared fires.
# Run: godot --headless --script res://tools/test_director_v3.gd

const RESULT := "res://tools/_director_v3_result.txt"

var _spawned: int = 0
var _spawn_times: Array = []
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
		+ "\tawait get_tree().create_timer(0.6).timeout\n" \
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
	var stub := _make_stub_scene()

	var sp_form = WaveDef.new()
	sp_form.enemy_scene = stub
	sp_form.count = 4
	sp_form.formation = 0
	sp_form.spawn_interval = 0.05
	var sp_fill = WaveDef.new()
	sp_fill.enemy_scene = stub
	sp_fill.count = 1
	sp_fill.formation = 0
	sp_fill.spawn_interval = 0.05

	var ph_form = Phrase.new()
	ph_form.kind = Phrase.Kind.FORMATION
	ph_form.specs = [sp_form]
	var ph_breath = Phrase.new()
	ph_breath.kind = Phrase.Kind.BREATHER
	ph_breath.duration = 0.5
	var ph_fill = Phrase.new()
	ph_fill.kind = Phrase.Kind.FILLER
	ph_fill.pool = [sp_fill]
	ph_fill.rate = 5.0
	ph_fill.until = &"budget"
	ph_fill.until_value = 5.0

	var w = ScoreWave.new()
	w.banner = "TEST"
	w.phrases.append(ph_form)
	w.phrases.append(ph_breath)
	w.phrases.append(ph_fill)
	var score = CombatScore.new()
	score.level_name = "v3"
	score.waves.append(w)

	var DirectorScript := load("res://scripts/levels/director.gd")
	var dir = DirectorScript.new()
	var holder := Node.new()
	get_root().add_child(holder)
	holder.add_child(dir)
	dir.enemy_spawned.connect(func(_p, _b):
		_spawn_times.append(_t)
		_spawned += 1)
	dir.level_cleared.connect(func(): _cleared = true)
	dir.start_score(score)


func _process(delta: float) -> bool:
	if not _started:
		_setup()
		_started = true
		return false
	_t += delta
	if _cleared or _t > 15.0:
		if _spawned != 9:
			_log.append("FAIL spawned=%d expected 9 (4 formation + 5 filler)" % _spawned)
		elif _spawn_times.size() >= 5:
			# Gap between last formation spawn (#4, idx 3) and first filler (#5, idx 4).
			var gap: float = _spawn_times[4] - _spawn_times[3]
			if gap < 0.4:
				_log.append("FAIL breather gap=%.2f (expected >=0.4)" % gap)
		if not _cleared:
			_log.append("FAIL level_cleared did not fire (t=%.1f)" % _t)
		if _log.is_empty():
			_log.append("DIRECTOR_V3 TEST: PASS (9 spawned, breather gap held, cleared)")
		else:
			_log.append("DIRECTOR_V3 TEST: FAIL")
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_log)))
			f.close()
		return true
	return false
