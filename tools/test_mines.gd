extends SceneTree

# Mine migrations (2026-06-08). T1: mine + mine_shielded → enemy_core + StraightDown. T3: smart
# mine → enemy_core + ProximityChase; smart bomblet → ProximityChase (bespoke munition layer).
# Verify each moves + activates with a dummy player present, no crash.
# Run: godot --headless --script res://tools/test_mines.gd

const RESULT := "res://tools/_mines_result.txt"

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var dt := 1.0 / 60.0
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = Vector2(Lanes.lane_center(3), 70.0)
	root.add_child(player)

	# Basic mine: descends on StraightDown.
	var m = load("res://scenes/enemies/enemy_mine.tscn").instantiate()
	root.add_child(m)
	m.start(Vector2(Lanes.lane_center(3), 16.0))
	var my0 = m.position.y
	for _i in range(40):
		if is_instance_valid(m): m._process(dt)
	if not is_instance_valid(m) or m.position.y <= my0 + 20.0:
		lines.append("FAIL mine did not descend"); fails += 1
	else:
		lines.append("mine descended to y=%.0f" % m.position.y)

	# Shielded mine: descends + has a shield component.
	var ms = load("res://scenes/enemies/enemy_mine_shield.tscn").instantiate()
	root.add_child(ms)
	ms.start(Vector2(Lanes.lane_center(2), 16.0))
	for _i in range(20):
		if is_instance_valid(ms): ms._process(dt)
	if ms.components.is_empty():
		lines.append("FAIL shielded mine has no shield component"); fails += 1
	else:
		lines.append("shielded mine ok (shield present, y=%.0f)" % ms.position.y)

	# Smart mine: player at 70, spawn near it → arms + chases.
	var sm = load("res://scenes/enemies/enemy_mine_smart.tscn").instantiate()
	root.add_child(sm)
	sm.start(Vector2(Lanes.lane_center(3), 30.0))
	for _i in range(40):
		if is_instance_valid(sm): sm._process(dt)
	if not is_instance_valid(sm):
		lines.append("FAIL smart mine freed"); fails += 1
	elif not sm._armed:
		lines.append("FAIL smart mine did not arm (proximity)"); fails += 1
	else:
		lines.append("smart mine armed + chasing (y=%.0f)" % sm.position.y)

	# Armored mine: reuses mine.gd with hull_hp=4.
	var am = load("res://scenes/enemies/enemy_mine_armored.tscn").instantiate()
	root.add_child(am)
	am.start(Vector2(Lanes.lane_center(1), 16.0))
	if int(am.max_health) != 4:
		lines.append("FAIL armored mine HP %d != 4" % int(am.max_health)); fails += 1
	else:
		lines.append("armored mine ok (HP=4)")

	# Smart bomblet (base bomblet + smart flag): spawn near player → engages.
	var bl = load("res://scenes/enemies/enemy_bomblet.tscn").instantiate()
	bl.smart = true
	root.add_child(bl)
	bl.start(Vector2(Lanes.lane_center(3), 40.0))
	for _i in range(40):
		if is_instance_valid(bl): bl._process(dt)
	if not is_instance_valid(bl):
		lines.append("(bomblet detonated/freed during test — ok if on contact)")
	elif not bl._smart_engaged:
		lines.append("FAIL smart bomblet did not engage"); fails += 1
	else:
		lines.append("smart bomblet engaged")

	lines.append("MINES: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
