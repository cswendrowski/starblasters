extends SceneTree

# Player marker rewiring (2026-06-09): weapons fire from the new scene markers (Muzzle /
# MuzzleWingL/R / LaunchWingL/R), not hardcoded offsets. Verify the offsets resolve to the
# authored marker positions and that the fire paths spawn without crashing.
# Run: godot --headless --script res://tools/test_player_markers.gd

const RESULT := "res://tools/_player_markers_result.txt"

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0

	var p = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(p)
	p.global_position = Vector2(240.0, 200.0)

	# Marker offsets resolve to the authored Ship-child positions.
	var muzzle: Vector2 = p._muzzle_offset("Ship/Muzzle", Vector2(99, 99))
	if absf(muzzle.x) > 1.0 or absf(muzzle.y + 8.0) > 1.0:   # Muzzle = (0,-8)
		lines.append("FAIL Muzzle offset %s != (0,-8)" % muzzle); fails += 1
	else:
		lines.append("Muzzle marker offset %s" % muzzle)
	var wingL: Vector2 = p._muzzle_offset("Ship/MuzzleWingL", Vector2(99, 99))
	if absf(wingL.x + 4.0) > 1.0:   # MuzzleWingL.x = -4
		lines.append("FAIL MuzzleWingL offset %s" % wingL); fails += 1
	else:
		lines.append("MuzzleWingL offset %s" % wingL)
	var launchR: Vector2 = p._muzzle_offset("Ship/LaunchWingR", Vector2(99, 99))
	if absf(launchR.x - 6.0) > 1.0:   # LaunchWingR.x = 6
		lines.append("FAIL LaunchWingR offset %s" % launchR); fails += 1
	else:
		lines.append("LaunchWingR offset %s" % launchR)

	# Primary fire spawns a bullet (from the Muzzle marker) without crashing.
	var before := root.get_child_count()
	p.can_shoot = true
	p.fire_primary()
	if root.get_child_count() <= before:
		lines.append("FAIL primary fired no bullet"); fails += 1
	else:
		lines.append("primary fired from marker")

	# Auto Laser tandem (wing muzzles) — must not crash.
	p.fire_tandem_alternating = true
	p.can_shoot = true
	p.fire_primary()
	lines.append("auto-laser tandem fired (wing muzzles)")

	lines.append("PLAYER MARKERS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
