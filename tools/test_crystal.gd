extends SceneTree

# Crystal honors any assigned movement pattern (2026-06-09). Crystal no longer hard-wires the
# pendulum stop-fire ("fire_on_phase"); it follows whatever the matrix assigns (loiter_high per the
# eligibility export) and fires on the standard ShootTimer cadence so it shoots under any pattern.
# Spawn it with a dummy player, assign a loiter pattern, tick, and assert it descends + holds and
# that generic timer firing is armed (fire_on_phase == "").
# Run: godot --headless --script res://tools/test_crystal.gd

const RESULT := "res://tools/_crystal_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const CRYSTAL := "res://scenes/enemies/core/enemy_crystal.tscn"

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = Vector2(Lanes.lane_center(3), 210.0)
	root.add_child(player)
	var dt := 1.0 / 60.0

	# Crystal on its NEW identity (loiter_high) + a spread weapon. It must descend toward the
	# hold band and arm generic timer firing (no pendulum-only phase-fire).
	var cps: PackedScene = load(CRYSTAL)
	var c = cps.instantiate()
	root.add_child(c)
	c.movement = Roster.make_movement({"movement": "loiter_high"})
	c.shoot_pattern = Roster.make_shoot({"shoot": "spread5", "bullet_variant": Roster.BV_SpreadPellet})
	c.start(Vector2(Lanes.lane_center(3), 16.0))
	var c_y0: float = c.position.y
	for _i in range(120):
		if is_instance_valid(c): c._process(dt)
	if not is_instance_valid(c):
		lines.append("FAIL crystal freed unexpectedly"); fails += 1
	elif c.position.y <= c_y0 + 20.0:
		lines.append("FAIL crystal did not descend on loiter (y0=%.0f y=%.0f)" % [c_y0, c.position.y]); fails += 1
	else:
		lines.append("crystal descended to y=%.0f on assigned loiter pattern" % c.position.y)
	# Generic firing: fire_on_phase must be empty so enemy_core arms the ShootTimer.
	if is_instance_valid(c) and String(c.fire_on_phase) != "":
		lines.append("FAIL crystal still phase-locked (fire_on_phase=%s)" % c.fire_on_phase); fails += 1
	else:
		lines.append("crystal firing is generic (fire_on_phase empty -> ShootTimer)")

	lines.append("CRYSTAL: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
