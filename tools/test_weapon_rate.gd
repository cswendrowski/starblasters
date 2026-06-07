extends SceneTree

# M6a.2 step 3: single-source fire rate. A Weapon's rate (inherited
# fire_interval_min/max) must flow to the enemy through the director's existing
# precedence (wave > pattern-claim > .tscn default), so the weapon is the single
# place rate is authored. Run: godot --headless --script res://tools/test_weapon_rate.gd

const RESULT := "res://tools/_weapon_rate_result.txt"
const DirectorScript := preload("res://scripts/levels/director.gd")
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const BulletScene := preload("res://scenes/projectiles/enemy_bullet.tscn")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	var world := Node2D.new()
	root.add_child(world)
	var director = DirectorScript.new()
	world.add_child(director)

	# Weapon authors the rate; no wave override -> pattern-claim wins.
	var w = Weapon.new()
	w.bullet_scene = BulletScene
	w.fire_pattern = Weapon.FirePattern.SINGLE
	w.fire_interval_min = 0.5
	w.fire_interval_max = 0.9

	var spec := WaveSpec.new()
	spec.enemy_scene = load("res://scenes/enemies/core/enemy_dart.tscn")
	spec.shoot_pattern_override = w
	spec.count = 1
	spec.formation = 0

	director._spawn_enemy(spec, 0)

	var found: Node = null
	for e in world.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			found = e
			break
	if found == null:
		lines.append("FAIL no enemy spawned"); fails += 1
	else:
		if not ("fire_interval_min" in found):
			lines.append("FAIL enemy has no fire_interval_min"); fails += 1
		else:
			if not is_equal_approx(found.fire_interval_min, 0.5):
				lines.append("FAIL rate not single-sourced: fire_interval_min=%.3f != 0.5" % found.fire_interval_min); fails += 1
			if not is_equal_approx(found.fire_interval_max, 0.9):
				lines.append("FAIL fire_interval_max=%.3f != 0.9" % found.fire_interval_max); fails += 1
		if "shoot_pattern" in found and found.shoot_pattern != w:
			lines.append("FAIL weapon not assigned as shoot_pattern"); fails += 1

	lines.append("WEAPON RATE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
