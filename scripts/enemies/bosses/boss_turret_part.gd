extends "res://scripts/enemies/bosses/boss_part.gd"

# Destructible TURRET part: a BossPart with a barrel sprite (recoil strip) plus
# commanded aim + fire. It is NOT autonomous — the boss's fire-mode coordinator
# decides when/where each turret fires (aim_to + fire), which is what lets the
# Shepherd run squad patterns (cycle / salvo / sweep) instead of N independent
# turrets. Reusable by any future multi-turret boss.

const EnemyBullet = preload("res://scenes/projectiles/projectile_ball.tscn")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

var bullet_variant: BulletVariant = null
var recoil_frames: int = 3
var _barrel: Sprite2D = null


func set_barrel(spr: Sprite2D) -> void:
	_barrel = spr


# Point the barrel along a WORLD-space direction (art authored nose-up).
func aim_to(world_dir: Vector2) -> void:
	if _barrel != null and is_instance_valid(_barrel) and world_dir != Vector2.ZERO:
		_barrel.rotation = world_dir.angle() + PI * 0.5


# Fire one bolt along a WORLD-space direction from the turret's position.
func fire(world_dir: Vector2) -> void:
	if _destroyed:
		return
	var dir := world_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	aim_to(dir)
	var tree := get_tree()
	if tree == null:
		return
	var b = EnemyBullet.instantiate()
	if bullet_variant != null and "variant" in b:
		b.variant = bullet_variant
	# Parent to the bench-aware gameplay world (== root in production) so the bolt
	# survives this part's queue_free and lands in the right viewport.
	BulletWorld.resolve(self, tree.root).add_child(b)
	if b.has_method("start"):
		b.start(global_position, dir)
	_recoil()


# Flick the barrel through its recoil frames (0 idle, 1..N) on a shot.
func _recoil() -> void:
	if _barrel == null or not is_instance_valid(_barrel) or _barrel.hframes < 2:
		return
	var last: int = mini(recoil_frames, _barrel.hframes - 1)
	_barrel.frame = 1
	var tw := _barrel.create_tween()
	tw.tween_interval(0.04)
	tw.tween_callback(func() -> void: if is_instance_valid(_barrel): _barrel.frame = last)
	tw.tween_interval(0.07)
	tw.tween_callback(func() -> void: if is_instance_valid(_barrel): _barrel.frame = 0)
