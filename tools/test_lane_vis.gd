extends SceneTree

# Smoke: the Lane Visualizer's CONDUCTOR path actually instantiates a real
# WaveDirector and streams a CombatScore (enemies appear). Mirrors main.gd's
# start_score, but through the dev tool. Run:
#   godot --headless --script res://tools/test_lane_vis.gd

const RESULT := "res://tools/_lane_vis_result.txt"

var _vis = null
var _started := false
var _t := 0.0
var _peak := 0
var _done := false


func _process(dt: float) -> bool:
	if _done:
		return true
	if _vis == null:
		var ps = load("res://scenes/dev/lane_visualizer.tscn")
		_vis = ps.instantiate()
		root.add_child(_vis)
		return false
	if not _started:
		_started = true
		var score = load("res://scripts/dev/combat_slice.gd").build()
		_vis._run_score(score)
		return false
	_t += dt
	var alive: int = get_nodes_in_group("enemies").size()
	_peak = maxi(_peak, alive)
	if _t > 3.6:
		_done = true
		var ok: bool = _peak > 0 and _vis._director != null
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("peak_alive=%d director=%s\nLANE VIS CONDUCTOR: %s" % [
				_peak, str(_vis._director != null), ("PASS" if ok else "FAIL")])
			f.close()
		quit()
	return false
