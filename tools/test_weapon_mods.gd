extends SceneTree

# M6b weapon multipliers. Verifies the faction/sector weapon-mod axis:
#   - Factions.apply(SUPREMACY) sets bullet_speed_mult (compounding) + faster fire.
#   - shoot_pattern scales a spawned bullet's speed by the enemy's mult, CLAMPED to the
#     clarity ceiling (480), and scales damage.
# Run: godot --headless --script res://tools/test_weapon_mods.gd

const RESULT := "res://tools/_weapon_mods_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const BulletScene := preload("res://scenes/projectiles/enemy_bullet.tscn")
const BV := preload("res://scripts/projectiles/bullet_variant.gd")
const Clarity := preload("res://scripts/systems/clarity.gd")

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _bullets() -> Array:
	return root.get_tree().get_nodes_in_group("bullets")


func _clear() -> void:
	for b in _bullets():
		b.free()


func _dart():
	var d = load("res://scenes/enemies/factions/privateer/enemy_dart.tscn").instantiate()
	root.add_child(d)
	d.position = Vector2(240, 60)
	return d


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# supremacy sets bullet_speed_mult (1.0 -> 1.25) + faster fire
	var ds = _dart()
	var fmin: float = ds.fire_interval_min
	Factions.apply(Factions.Id.SUPREMACY, ds)
	if not is_equal_approx(ds.bullet_speed_mult, 1.25):
		_fail("supremacy bullet_speed_mult %.3f != 1.25" % ds.bullet_speed_mult)
	if not is_equal_approx(ds.fire_interval_min, fmin * 0.7):
		_fail("supremacy fire_rate not applied")
	ds.free()

	# spawn scaling: laser (420) * 2.0 -> clamped to 480
	var v = BV.new(); v.speed = 420.0; v.damage = 1; v.lifetime = 5.0
	var w = Weapon.new()
	w.bullet_scene = BulletScene
	w.fire_pattern = Weapon.FirePattern.SINGLE
	w.payload = v
	var d1 = _dart()
	d1.bullet_speed_mult = 2.0
	w.fire(d1)
	var bs := _bullets()
	if bs.size() != 1:
		_fail("expected 1 bullet, got %d" % bs.size())
	elif not is_equal_approx(bs[0].speed, Clarity.ABS_MAX_SPEED):
		_fail("speed mult not clamped to ceiling: %.1f != %.1f" % [bs[0].speed, Clarity.ABS_MAX_SPEED])
	_clear(); d1.free()

	# spawn scaling under the ceiling: 420 * 1.1 = 462
	var d2 = _dart()
	d2.bullet_speed_mult = 1.1
	w.fire(d2)
	var bs2 := _bullets()
	if bs2.size() == 1 and not is_equal_approx(bs2[0].speed, 462.0):
		_fail("speed mult (1.1) = %.1f != 462" % bs2[0].speed)
	_clear(); d2.free()

	# damage mult: payload dmg 1 * 3 -> 3
	var d3 = _dart()
	d3.bullet_damage_mult = 3.0
	w.fire(d3)
	var bs3 := _bullets()
	if bs3.size() == 1 and bs3[0].damage != 3:
		_fail("damage mult = %d != 3" % bs3[0].damage)
	_clear(); d3.free()

	_lines.append("WEAPON MODS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
