extends Node
# Smoke: boot a combat level with the new 5x3 wave structure and confirm the director performs it —
# enemies actually spawn (no crash in the restructured score path).
const RESULT := "res://tools/_combat_play_result.txt"
var _t := 0
var _main: Node = null
var _peak := 0
func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null: run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
func _process(_dt: float) -> void:
	_t += 1
	var n := get_tree().get_nodes_in_group("enemies").size()
	_peak = maxi(_peak, n)
	if _t >= 240:
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("peak enemies alive over 240 frames: %d (expect > 0)\nCOMBAT PLAY: %s" % [_peak, ("PASS" if _peak > 0 else "FAIL")])
			f.close()
		get_tree().quit()
