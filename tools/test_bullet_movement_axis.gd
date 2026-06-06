extends SceneTree

# M6a.2 step 1: projectile-movement axis on base_bullet. Verifies the bullet's OWN
# homing_rate/wobble fields drive movement (so the firing layer can set them without a
# variant), homing is target-group-aware, and _apply_variant still seeds the fields
# from a variant (behavior-preserving). Run:
#   godot --headless --script res://tools/test_bullet_movement_axis.gd

const RESULT := "res://tools/_bullet_axis_result.txt"
const BulletScene := preload("res://scenes/projectiles/enemy_bullet.tscn")
const BulletVariantC := preload("res://scripts/projectiles/bullet_variant.gd")

const DT := 1.0 / 60.0
var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	# A target in the "player" group (enemy bullets home this group).
	var target := Node2D.new()
	target.position = Vector2(320, 100)
	root.add_child(target)
	target.add_to_group("player")

	# --- homing (no variant; field set directly by the "firing layer") ---
	var hb = BulletScene.instantiate()
	hb.variant = null
	root.add_child(hb)          # _ready: variant null, so homing_rate stays as we set
	hb.set_process(false)       # we tick manually
	hb.homing_rate = 140.0
	hb.start(Vector2(240, 100), Vector2(0, 1))   # heading straight down
	for i in 30:
		hb._process(DT)
	if hb.velocity_dir.x <= 0.05:
		lines.append("FAIL homing: did not steer toward target on the right (dir.x=%.3f)" % hb.velocity_dir.x); fails += 1

	# --- wobble (field set directly, no variant) ---
	var wb = BulletScene.instantiate()
	wb.variant = null
	root.add_child(wb)
	wb.set_process(false)
	wb.homing_rate = 0.0
	wb.wobble_amplitude = 8.0
	wb.wobble_frequency = 3.0
	wb.start(Vector2(240, 40), Vector2(0, 1))
	var max_dev := 0.0
	for i in 30:
		wb._process(DT)
		max_dev = maxf(max_dev, absf(wb.global_position.x - 240.0))
	if max_dev < 1.0:
		lines.append("FAIL wobble: no perpendicular deviation (max %.2f)" % max_dev); fails += 1

	# --- variant seeding (behavior-preserving) ---
	var v = BulletVariantC.new()
	v.speed = 60.0
	v.damage = 1
	v.lifetime = 5.0
	v.homing_rate = 77.0
	v.wobble_amplitude = 5.0
	v.wobble_frequency = 2.0
	var vb = BulletScene.instantiate()
	vb.variant = v
	root.add_child(vb)          # _ready -> _apply_variant copies movement into fields
	if not is_equal_approx(vb.homing_rate, 77.0):
		lines.append("FAIL variant seed homing_rate=%.2f != 77" % vb.homing_rate); fails += 1
	if not is_equal_approx(vb.wobble_amplitude, 5.0):
		lines.append("FAIL variant seed wobble_amplitude=%.2f != 5" % vb.wobble_amplitude); fails += 1

	lines.append("homing dir.x=%.3f ; wobble dev=%.2f ; variant-seeded homing=%.0f wobble=%.0f" % [
		hb.velocity_dir.x, max_dev, vb.homing_rate, vb.wobble_amplitude])
	lines.append("BULLET MOVEMENT AXIS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
