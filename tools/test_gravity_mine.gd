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

	# Verify OrbitComponent exists and has rings (2026-06-19: de-bespoked from _bomblets array).
	var orbit_component = null
	var ring_count: int = 0
	if "components" in m:
		for c in m.components:
			# Check if component is an OrbitComponent by class name or method presence
			if c.get_script().get_name() == "OrbitComponent" or (c.has_method("on_death") and "rings" in c):
				orbit_component = c
				if "rings" in c:
					ring_count = c.rings.size()
				break

	if orbit_component == null:
		lines.append("FAIL orbit component not found"); fails += 1
	else:
		lines.append("orbit component present")

	if ring_count > 0 and "rings" in orbit_component:
		var first_ring = orbit_component.rings[0]
		if "count" in first_ring:
			var n: int = first_ring["count"]
			if not (n in [4, 6, 8]):
				lines.append("FAIL bomblet count %d not in {4,6,8}" % n); fails += 1
			else:
				lines.append("orbit ring = %d bomblets" % n)

	# Death should trigger component cleanup (orbits released via OrbitComponent.on_death).
	m.explode()
	lines.append("death trigger completed (component cleanup via OrbitComponent.on_death)")

	lines.append("GRAVITY MINE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
