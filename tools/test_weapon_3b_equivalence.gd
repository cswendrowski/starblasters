extends SceneTree

# Weapons 3b equivalence harness (2026-06-13). Proves the unified Weapon resource
# fires bullets IDENTICALLY to the legacy SingleShot/AimedShot/SpreadShot/BurstShot
# classes it replaced in the roster/levels producers — so migrating make_shoot +
# levels_v2 + wave_generator onto Weapon is behavior-preserving for the whole roster.
#
# For each shape it fires both patterns at a dummy enemy (with a dummy player in the
# tree) and compares the spawned bullets' direction set + speed + count.
# Run: godot --headless --script res://tools/test_weapon_3b_equivalence.gd

const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")
const AimedShot  = preload("res://scripts/enemies/shoot_patterns/aimed_fire.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const BurstShot  = preload("res://scripts/enemies/shoot_patterns/burst_shot.gd")
const Weapon     = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")
const Playfield  = preload("res://scripts/playfield.gd")

const EPS := 0.001

var _world: Node2D


var _ran := false


# Run on the first real frame, not in _init — nodes added during SceneTree._init
# don't have a live tree yet, so enemy.get_tree() is null and aimed/burst can't
# resolve the player (they'd both fall back to straight-down and "match" trivially).
func _process(_dt: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	var player := Area2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(Playfield.CENTER.x + 40.0, 250.0)
	_world.add_child(player)

	var lines: Array = []
	var fails := 0

	# SINGLE — straight down.
	fails += _cmp("single", _legacy_single(), _weapon_single(), lines)
	# AIMED — at the player (lead 0).
	fails += _cmp("aimed", _legacy_aimed(), _weapon_aimed(), lines)
	# SPREAD — 5 @ 36deg symmetric fan.
	fails += _cmp("spread5", _legacy_spread(), _weapon_spread(), lines)
	# BURST — first (synchronous) shot; the await tail spaces identical shots in time.
	fails += _cmp("burst(first)", _legacy_burst(), _weapon_burst(), lines)

	lines.append("WEAPON 3b EQUIVALENCE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	print("\n".join(PackedStringArray(lines)))
	quit(0 if fails == 0 else 1)


# --- pattern builders (legacy vs Weapon, mirroring make_shoot) -----------------
func _legacy_single():
	var s = SingleShot.new(); s.bullet_scene = EnemyBullet; return s
func _weapon_single():
	var w = Weapon.new(); w.bullet_scene = EnemyBullet
	w.fire_pattern = Weapon.FirePattern.SINGLE; w.aim = Weapon.Aim.STRAIGHT_DOWN; return w

func _legacy_aimed():
	var s = AimedShot.new(); s.bullet_scene = EnemyBullet; return s
func _weapon_aimed():
	var w = Weapon.new(); w.bullet_scene = EnemyBullet
	w.fire_pattern = Weapon.FirePattern.AIMED; w.aim = Weapon.Aim.AT_PLAYER; return w

func _legacy_spread():
	var s = SpreadShot.new(); s.bullet_scene = EnemyBullet
	s.bullet_count = 5; s.spread_degrees = 36.0; return s
func _weapon_spread():
	var w = Weapon.new(); w.bullet_scene = EnemyBullet
	w.fire_pattern = Weapon.FirePattern.SPREAD; w.aim = Weapon.Aim.STRAIGHT_DOWN
	w.spread_count = 5; w.spread_degrees = 36.0; return w

func _legacy_burst():
	var s = BurstShot.new(); s.bullet_scene = EnemyBullet
	s.burst_count = 3; s.burst_interval = 0.18; return s
func _weapon_burst():
	var w = Weapon.new(); w.bullet_scene = EnemyBullet
	w.fire_pattern = Weapon.FirePattern.BURST; w.aim = Weapon.Aim.STRAIGHT_DOWN
	w.burst_count = 3; w.burst_interval = 0.18; return w


# --- harness -------------------------------------------------------------------
func _enemy() -> Area2D:
	var e := Area2D.new()
	e.global_position = Vector2(Playfield.CENTER.x - 20.0, 120.0)  # left of center, above player
	_world.add_child(e)
	return e


# Fire `pattern` once and return the spawned bullets' {dir, speed}, sorted by angle.
func _collect(pattern) -> Array:
	var e := _enemy()
	var before := {}
	for c in _world.get_children():
		before[c.get_instance_id()] = true
	pattern.fire(e)
	var out: Array = []
	for c in _world.get_children():
		if before.has(c.get_instance_id()):
			continue
		if ("velocity_dir" in c) and ("speed" in c):
			out.append({"dir": (c.velocity_dir as Vector2).normalized(), "speed": float(c.speed)})
	out.sort_custom(func(a, b): return atan2(a.dir.y, a.dir.x) < atan2(b.dir.y, b.dir.x))
	return out


func _cmp(name: String, legacy, weap, lines: Array) -> int:
	var a := _collect(legacy)
	var b := _collect(weap)
	if a.size() != b.size():
		lines.append("FAIL %s: bullet count legacy=%d weapon=%d" % [name, a.size(), b.size()])
		return 1
	if a.size() == 0:
		lines.append("FAIL %s: no bullets spawned" % name)
		return 1
	for i in a.size():
		var da: Vector2 = a[i].dir
		var db: Vector2 = b[i].dir
		if da.distance_to(db) > EPS or absf(a[i].speed - b[i].speed) > EPS:
			lines.append("FAIL %s[%d]: legacy dir=%s spd=%.1f | weapon dir=%s spd=%.1f"
				% [name, i, str(da), a[i].speed, str(db), b[i].speed])
			return 1
	lines.append("ok   %s: %d bullet(s) match (dir+speed)" % [name, a.size()])
	return 0
