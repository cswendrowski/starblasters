extends SceneTree

# Driven test for ShipDamageTells wired into live enemy_base. Spawns real ship enemies, lets the
# deferred attach run, and asserts: tells attach with the right per-size preset, marker weights are
# UNIFORM, the overlay sensitivity tracks set_damage during life, and a lethal hit delegates the
# death (disintegrate + per-size VFX) to the tell system. Run: godot --headless -s tools/test_damage_tells_live.gd

const ShipDamageTells = preload("res://scripts/effects/ship_damage_tells.gd")
const SCENES := [
	"res://scenes/enemies/core/enemy_hover.tscn",
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn",
	"res://scenes/enemies/core/enemy_bomber.tscn",
]


func _initialize() -> void:
	_run.call_deferred()


func _test_scene(path: String) -> bool:
	var ok := true
	var world := Node2D.new(); root.add_child(world)
	var e = load(path).instantiate()
	world.add_child(e)
	e.position = Vector2(240.0, 135.0)
	e.offscreen_margin = 100000.0
	await process_frame   # deferred _attach_damage_tells runs

	if e._dmg_tells == null or not is_instance_valid(e._dmg_tells):
		print("  FAIL %s: no tells attached" % path)
		world.queue_free(); await process_frame
		return false

	# (1) right per-size preset.
	var spr: Sprite2D = e.get_node("Sprite2D")
	var ss: float = e._tells_size_scale(spr)
	var cat := ShipDamageTells.size_category(ss)
	var expected: Dictionary = ShipDamageTells.cfg_for_size(ss)
	var cfg: Dictionary = e._dmg_tells._cfg
	for key in ["max_sens", "spark_amount", "debris", "burn_trails", "spark_start"]:
		if absf(float(cfg[key]) - float(expected[key])) > 0.001:
			print("  FAIL %s: cfg[%s]=%s expected %s" % [path, key, cfg[key], expected[key]]); ok = false

	# (2) uniform marker weights + LAZY: no emitter nodes built before any damage.
	for s in e._dmg_tells._sparks:
		if absf(float(s["weight"]) - 1.0) > 0.001:
			print("  FAIL %s: non-uniform marker weight %s" % [path, s["weight"]]); ok = false
			break
		if s["parts"] != null:
			print("  FAIL %s: spark emitter built before damage (not lazy)" % path); ok = false
			break
	for slot in e._dmg_tells._burn_slots:
		if slot["trail"] != null:
			print("  FAIL %s: burn trail built before damage (not lazy)" % path); ok = false
			break

	# (3) life ramp: overlay sensitivity tracks the damage fraction × max_sens.
	e.max_health = 10
	e.health = 10
	e.take_hit(3)   # → health 7 → set_damage(0.3)
	var mat = spr.material
	var sens: float = float(mat.get_shader_parameter("sensitivity")) if mat != null else -1.0
	var want: float = 0.3 * float(expected["max_sens"])
	if absf(sens - want) > 0.02:
		print("  FAIL %s: sensitivity %.3f want %.3f" % [path, sens, want]); ok = false
	# At least one spark should be lit by 30% damage.
	var any_lit := false
	for s in e._dmg_tells._sparks:
		if bool(s["lit"]):
			any_lit = true; break
	if not any_lit:
		print("  FAIL %s: no spark lit at 30%% damage" % path); ok = false

	# (4) lethal hit delegates the death to the tell system.
	e.health = 1
	e.take_hit(5)
	if not e._dmg_tells._destroyed:
		print("  FAIL %s: death not delegated to tells" % path); ok = false

	print(("  PASS [%s] " % cat) + path if ok else ("  ---- [%s] " % cat) + path)
	world.queue_free(); await process_frame
	return ok


func _run() -> void:
	var ok := true
	for path in SCENES:
		ok = (await _test_scene(path)) and ok
	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit()
