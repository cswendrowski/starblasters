extends SceneTree

# M6a.2 step 5: movement axis on the BASE shoot_pattern + roster wiring restores the
# plasma wobble via the FIRING LAYER (not the bullet .tres). Verifies make_shoot
# stamps the axis from entry keys, and any base pattern (aimed_fire) applies it to
# spawned bullets. Run: godot --headless --script res://tools/test_weapon_axis_restore.gd

const RESULT := "res://tools/_weapon_axis_restore_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const BulletVariantC := preload("res://scripts/projectiles/bullet_variant.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	var pv = BulletVariantC.new()
	pv.speed = 60.0; pv.damage = 1; pv.lifetime = 5.0

	# make_shoot wires the axis from entry keys (the Weaver pattern).
	var entry := {
		"shoot": "aimed",
		"bullet_variant": pv,
		"wobble_amplitude": 8.0,
		"wobble_frequency": 3.0,
	}
	var pat = Roster.make_shoot(entry)
	if pat == null:
		lines.append("FAIL make_shoot returned null"); fails += 1
	elif not is_equal_approx(pat.wobble_amplitude, 8.0):
		lines.append("FAIL pattern wobble_amplitude=%.2f != 8" % pat.wobble_amplitude); fails += 1

	# Firing it stamps wobble onto the bullet (firing-layer driven).
	if pat != null:
		var enemy := Node2D.new()
		enemy.position = Vector2(240, 60)
		root.add_child(enemy)
		var player := Node2D.new()
		player.position = Vector2(240, 200)
		root.add_child(player)
		player.add_to_group("player")
		pat.fire(enemy)
		var bs := root.get_tree().get_nodes_in_group("bullets")
		if bs.size() < 1:
			lines.append("FAIL no bullet spawned"); fails += 1
		elif not is_equal_approx(bs[0].wobble_amplitude, 8.0):
			lines.append("FAIL spawned bullet wobble_amplitude=%.2f != 8 (axis not applied)" % bs[0].wobble_amplitude); fails += 1

	# Sanity: an entry WITHOUT the keys leaves the axis at 0 (variant default wins).
	var plain = Roster.make_shoot({"shoot": "single", "bullet_variant": pv})
	if plain != null and plain.wobble_amplitude != 0.0:
		lines.append("FAIL plain pattern got nonzero wobble (%.2f)" % plain.wobble_amplitude); fails += 1

	lines.append("WEAPON AXIS RESTORE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
