extends SceneTree

# M6a.2 step 2: the Weapon resource. Fires each fire_pattern at a dummy enemy and
# verifies the right number of bullets spawn, carry the payload variant, the aim is
# applied, and the movement axis stamps onto the spawned bullets. Run:
#   godot --headless --script res://tools/test_weapon_resource.gd

const RESULT := "res://tools/_weapon_resource_result.txt"
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const BulletScene := preload("res://scenes/projectiles/enemy_bullet.tscn")
const BulletVariantC := preload("res://scripts/projectiles/bullet_variant.gd")

var _done := false


func _bullets() -> Array:
	return root.get_tree().get_nodes_in_group("bullets")


func _clear_bullets() -> void:
	for b in _bullets():
		b.free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	var enemy := Node2D.new()
	enemy.position = Vector2(240, 60)
	root.add_child(enemy)

	var pv = BulletVariantC.new()
	pv.speed = 60.0; pv.damage = 1; pv.lifetime = 5.0

	# SINGLE + movement axis (homing) — one bullet, payload set, homing stamped.
	var w = Weapon.new()
	w.bullet_scene = BulletScene
	w.fire_pattern = Weapon.FirePattern.SINGLE
	w.payload = pv
	w.homing_rate = 120.0
	w.fire(enemy)
	var bs := _bullets()
	if bs.size() != 1:
		lines.append("FAIL SINGLE spawned %d != 1" % bs.size()); fails += 1
	elif bs[0].variant != pv:
		lines.append("FAIL SINGLE payload not applied"); fails += 1
	elif not is_equal_approx(bs[0].homing_rate, 120.0):
		lines.append("FAIL SINGLE axis homing=%.1f != 120" % bs[0].homing_rate); fails += 1
	_clear_bullets()

	# SPREAD — spread_count bullets with diverging headings.
	var w2 = Weapon.new()
	w2.bullet_scene = BulletScene
	w2.fire_pattern = Weapon.FirePattern.SPREAD
	w2.payload = pv
	w2.spread_count = 5
	w2.spread_degrees = 40.0
	w2.fire(enemy)
	var sp := _bullets()
	if sp.size() != 5:
		lines.append("FAIL SPREAD spawned %d != 5" % sp.size()); fails += 1
	else:
		var xs := {}
		for b in sp:
			xs[snappedf(b.velocity_dir.x, 0.01)] = true
		if xs.size() < 3:
			lines.append("FAIL SPREAD headings not diverging (%d distinct)" % xs.size()); fails += 1
	_clear_bullets()

	# AIMED — bullet steered toward a player to the right.
	var player := Node2D.new()
	player.position = Vector2(330, 200)
	root.add_child(player)
	player.add_to_group("player")
	var w3 = Weapon.new()
	w3.bullet_scene = BulletScene
	w3.fire_pattern = Weapon.FirePattern.AIMED
	w3.payload = pv
	w3.fire(enemy)
	var am := _bullets()
	if am.size() != 1:
		lines.append("FAIL AIMED spawned %d != 1" % am.size()); fails += 1
	elif am[0].velocity_dir.x <= 0.05:
		lines.append("FAIL AIMED not aimed toward player on the right (dir.x=%.3f)" % am[0].velocity_dir.x); fails += 1
	_clear_bullets()

	# BURST — first bullet fires immediately (the rest are timed awaits).
	var w4 = Weapon.new()
	w4.bullet_scene = BulletScene
	w4.fire_pattern = Weapon.FirePattern.BURST
	w4.payload = pv
	w4.burst_count = 3
	w4.fire(enemy)
	if _bullets().size() < 1:
		lines.append("FAIL BURST first bullet not immediate"); fails += 1
	_clear_bullets()

	lines.append("WEAPON RESOURCE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
