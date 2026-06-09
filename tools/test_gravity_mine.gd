extends SceneTree

# Gravity Mine (2026-06-09): 4 HP, a ring of 4/6/8 bomblets orbiting at orbit_radius, released on
# death (cleared from the ring). Run: godot --headless --script res://tools/test_gravity_mine.gd

const RESULT := "res://tools/_gravity_mine_result.txt"

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
	player.position = Vector2(Lanes.lane_center(3), 240.0)
	root.add_child(player)

	var m = load("res://scenes/enemies/enemy_mine_gravity.tscn").instantiate()
	root.add_child(m)
	m.start(Vector2(Lanes.lane_center(3), 60.0))
	if int(m.max_health) != 4:
		lines.append("FAIL gravity HP %d != 4" % int(m.max_health)); fails += 1
	else:
		lines.append("gravity mine HP=4")

	for _i in range(8):
		if is_instance_valid(m): m._process(dt)
	var n: int = m._bomblets.size()
	if not (n in [4, 6, 8]):
		lines.append("FAIL bomblet count %d not in {4,6,8}" % n); fails += 1
	else:
		lines.append("orbit ring = %d bomblets" % n)
	if n > 0:
		var b = m._bomblets[0]["node"]
		var d: float = b.global_position.distance_to(m.global_position)
		if absf(d - float(m.orbit_radius)) > 3.0:
			lines.append("FAIL bomblet off-orbit (d=%.1f vs r=%.1f)" % [d, m.orbit_radius]); fails += 1
		else:
			lines.append("bomblet on ring (d=%.1f ~ r=%.1f)" % [d, m.orbit_radius])

	# Death releases the ring (cleared from the mine's tracking).
	m.explode()
	if not m._bomblets.is_empty():
		lines.append("FAIL bomblets not released on death (%d left)" % m._bomblets.size()); fails += 1
	else:
		lines.append("bomblets released on death")

	lines.append("GRAVITY MINE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
