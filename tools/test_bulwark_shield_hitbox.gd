extends SceneTree

# Bulwark oversized-shield hitbox (2026-07-19). The bulwark's shield bubble is far larger
# than its hull so it can cover allies; the scene authors a CollisionOuterShield circle that
# ShieldComponent must (a) size to the fit-resolved bubble (ring_size 96 → radius 48) and
# (b) keep live ONLY while the shield holds charges. This spawns a real bulwark, waits for
# the deferred component start, asserts the sized+enabled state, drains all 4 charges via
# take_hit, and asserts the shape disables (and hull HP stayed untouched while shielded).
#   godot --headless --script res://tools/test_bulwark_shield_hitbox.gd

const SCENE := "res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn"

var _frame := 0
var _fails := 0
var _enemy = null
var _shape: CollisionShape2D = null


func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("  %s  %s" % [("OK  " if ok else "FAIL"), label])


func _process(_dt: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_enemy = load(SCENE).instantiate()
			root.add_child(_enemy)
			_enemy.position = Vector2(240, 135)
		4:
			# Deferred _components_start + set_deferred("disabled") have both flushed by now.
			_shape = _enemy.get_node_or_null("CollisionOuterShield")
			print("shield up (4 charges):")
			_check("CollisionOuterShield node present", _shape != null)
			if _shape == null:
				return true
			_check("circle radius sized to fit (48): %.1f" % (_shape.shape as CircleShape2D).radius,
				is_equal_approx((_shape.shape as CircleShape2D).radius, 48.0))
			_check("shape ENABLED while shielded", not _shape.disabled)
			var hp0: int = _enemy.health
			for i in 4:
				_enemy.take_hit(1)
			_check("4 shielded hits left hull untouched (%d -> %d)" % [hp0, _enemy.health],
				_enemy.health == hp0)
		6:
			print("shield broken (0 charges):")
			_check("shape DISABLED with shield down", _shape.disabled)
			print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
			_enemy.queue_free()
			return true
	return false
