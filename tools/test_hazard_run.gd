extends SceneTree

# Integration: a converted minefield CombatScore actually streams mines through the
# real WaveDirector (mines instantiate under the conductor, land in the "enemies"
# group, flagged is_hazard). Run:
#   godot --headless --script res://tools/test_hazard_run.gd

const RESULT := "res://tools/_hazard_run_result.txt"
const LV := preload("res://scripts/levels/levels_v2.gd")
const DirectorScript := preload("res://scripts/levels/director.gd")

var _world = null
var _dir = null
var _started := false
var _t := 0.0
var _peak := 0
var _hazard_seen := false
var _done := false


func _process(dt: float) -> bool:
	if _done:
		return true
	if _world == null:
		_world = Node2D.new()
		root.add_child(_world)
		_dir = DirectorScript.new()
		_world.add_child(_dir)
		return false
	if not _started:
		_started = true
		_dir.start_score(LV.build_minefield_score())
		return false
	_t += dt
	var grp = get_nodes_in_group("enemies")
	_peak = maxi(_peak, grp.size())
	for n in grp:
		if "is_hazard" in n and n.is_hazard:
			_hazard_seen = true
	if _t > 3.2:
		_done = true
		var ok: bool = _peak > 0 and _hazard_seen
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("peak_alive=%d hazard_seen=%s\nHAZARD RUN: %s" % [
				_peak, str(_hazard_seen), ("PASS" if ok else "FAIL")])
			f.close()
		quit()
	return false
