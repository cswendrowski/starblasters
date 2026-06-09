extends SceneTree

# Beam shooter migration + BROADSIDE weapon (2026-06-08). Beam shooter now extends enemy_core +
# BeamSweep/Drift movement, keeping the shared BeamEmitter + hull-aim. BROADSIDE is salvaged from
# the frigate into the weapon system. Verify both headlessly (no visual check).
# Run: godot --headless --script res://tools/test_beam_broadside.gd

const RESULT := "res://tools/_beam_broadside_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")

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
	player.position = Vector2(Lanes.lane_center(3), 210.0)
	root.add_child(player)

	# Beam shooter (SWEEP): descends to ~58, attaches a beam, sweeps.
	var bs = load("res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn").instantiate()
	root.add_child(bs)
	bs.movement = Roster.make_movement({"movement": "beam_sweep"})
	bs.start(Vector2(Lanes.lane_center(2), 8.0))
	for _i in range(120):
		if is_instance_valid(bs): bs._process(dt)
	if not is_instance_valid(bs):
		lines.append("FAIL beam shooter freed"); fails += 1
	elif absf(bs.global_position.y - 58.0) > 14.0:
		lines.append("FAIL beam shooter did not settle (y=%.1f)" % bs.global_position.y); fails += 1
	elif bs._beam == null or not is_instance_valid(bs._beam):
		lines.append("FAIL beam shooter has no beam"); fails += 1
	else:
		lines.append("beam shooter settled y=%.1f, beam attached, started=%s" % [bs.global_position.y, bs._beam_started])

	# BROADSIDE weapon: builds + fires a flank gun without crashing.
	var w = Roster.make_shoot({"shoot": "broadside", "bullet_variant": Roster.BV_HeavySlug})
	if w == null or not (w is Weapon) or w.fire_pattern != Weapon.FirePattern.BROADSIDE:
		lines.append("FAIL broadside weapon not built"); fails += 1
	else:
		var dummy := Area2D.new()
		dummy.add_to_group("enemies")
		dummy.global_position = Vector2(Lanes.lane_center(3), 100.0)
		root.add_child(dummy)
		var before := root.get_child_count()
		w.fire(dummy)
		w.fire(dummy)
		var after := root.get_child_count()
		var gun := int(dummy.get_meta("_broadside_gun", -1))
		if after <= before:
			lines.append("FAIL broadside fired no bullets (%d->%d)" % [before, after]); fails += 1
		else:
			lines.append("broadside fired %d bullets, gun cycle=%d" % [after - before, gun])

	lines.append("BEAM+BROADSIDE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
