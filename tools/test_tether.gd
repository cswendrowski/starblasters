extends SceneTree

# Non-boss Tether Mine (2026-06-09): 4 HP, begins DORMANT (no player), wakes when the player enters
# tether_range. Run: godot --headless --script res://tools/test_tether.gd

const RESULT := "res://tools/_tether_result.txt"

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var dt := 1.0 / 60.0

	var t = load("res://scenes/enemies/enemy_mine_tether.tscn").instantiate()
	root.add_child(t)
	t.start(Vector2(Lanes.lane_center(3), 60.0))
	if int(t.max_health) != 4:
		lines.append("FAIL tether HP %d != 4" % int(t.max_health)); fails += 1
	else:
		lines.append("non-boss tether HP=4")

	# No player → stays DORMANT (enum value 0).
	for _i in range(5):
		if is_instance_valid(t): t._process(dt)
	if t._phase != 0:
		lines.append("FAIL not dormant without player (phase=%d)" % t._phase); fails += 1
	else:
		lines.append("dormant with no player")

	# Player within tether_range → wakes (phase advances past DORMANT).
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = t.global_position + Vector2(20.0, 0.0)
	root.add_child(player)
	for _i in range(10):
		if is_instance_valid(t): t._process(dt)
	if t._phase == 0:
		lines.append("FAIL did not wake on proximity"); fails += 1
	else:
		lines.append("woke on player proximity (phase=%d)" % t._phase)

	lines.append("TETHER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
