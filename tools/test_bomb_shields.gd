extends SceneTree

# Shield-unification acceptance (shield_unification_2026-06-08.md): a smart bomb (18 dmg)
# ignores CHARGE shields (kills them) but only out-damages a POOL sapper whose banked pool
# is smaller than the bomb. Exercises the real ShieldComponent + smart_bomb_shockwave.
# Run: godot --headless --script res://tools/test_bomb_shields.gd

const RESULT := "res://tools/_bomb_shields_result.txt"
const ShieldComp := preload("res://scripts/enemies/components/shield_component.gd")
const Bomb := preload("res://scripts/projectiles/smart_bomb_shockwave.gd")
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")

var _lines: Array = []
var _fails := 0
var _frame := 0
var _phase := 0
var _done := false
var _world
var _charge_e
var _pool_weak
var _pool_fed


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _spawn(mode: int, cap: int, hp: int):
	var dart = load("res://scenes/enemies/factions/privateer/enemy_dart.tscn").instantiate()
	var mv = StraightDown.new(); mv.speed = 0.0
	dart.movement = mv
	var sc = ShieldComp.new(); sc.mode = mode; sc.capacity = cap; sc.regen_interval = 0.0
	dart.components = [sc]
	_world.add_child(dart)
	dart.max_health = hp; dart.health = hp
	dart.start(Vector2(240, 60))
	return dart


func _dead(e) -> bool:
	return (not is_instance_valid(e)) or e._dying


func _process(_dt: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _phase == 0:
		_world = Node2D.new(); root.add_child(_world)
		_charge_e = _spawn(ShieldComp.Mode.CHARGE, 3, 8)   # CHARGE, 8 HP < 18 → bomb kills
		_pool_weak = _spawn(ShieldComp.Mode.POOL, 2, 8)    # POOL pool 2 < 18 → dies
		_pool_fed = _spawn(ShieldComp.Mode.POOL, 2, 8)     # POOL, banked to 22 ≥ 18 → survives
		_phase = 1
		return false
	if _phase == 1:
		if _frame < 6:                                     # let deferred on_start init shields
			return false
		_pool_fed._components[0].bank(20.0)                # pool 2 + 20 = 22 ≥ 18
		var b = Bomb.new()
		b.configure(18, Vector2(240, 60))
		_world.add_child(b)
		_phase = 2
		return false
	if _frame < 14:                                        # let the wave sweep + deaths resolve
		return false
	if not _dead(_charge_e):
		_fail("CHARGE-shielded enemy survived the bomb")
	if not _dead(_pool_weak):
		_fail("weak POOL sapper (pool<18) survived the bomb")
	if _dead(_pool_fed):
		_fail("fed POOL sapper (pool>=18) was killed by the bomb")
	_lines.append("charge_dead=%s weak_pool_dead=%s fed_pool_alive=%s" % [
		_dead(_charge_e), _dead(_pool_weak), not _dead(_pool_fed)])
	_lines.append("BOMB SHIELDS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	_done = true
	quit()
	return true
