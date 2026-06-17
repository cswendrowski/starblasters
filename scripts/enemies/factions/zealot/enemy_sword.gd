extends "res://scripts/enemies/enemy_core.gd"

# Sword — zealot lane pusher with a rolling BROADSIDE (Roman 2026-06-08). Cycles its
# body muzzles (Muzzle1..N down the centerline, via EnemyBase's next_muzzle_pos) firing
# straight DOWN on a fast beat, so a stream of shots rolls down the hull — perpendicular
# to travel on a horizontal cross (a broadside curtain), forward on a descent. Faster
# shots than the old slow single (fast_pellet @ 300). Movement from the roster slot;
# only the firing is bespoke (library bullet via a BulletVariant).

const BULLET = preload("res://scenes/projectiles/enemy_bullet.tscn")
const SHOT = preload("res://data/bullets/fast_pellet.tres")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
const ZealotTurret = preload("res://scripts/enemies/factions/zealot/zealot_turret.gd")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

const FIRE_INTERVAL := 0.18   # fast roll down the guns

var _fire_t: float = 0.0


func _ready() -> void:
	super._ready()
	_fire_t = randf_range(0.0, FIRE_INTERVAL)
	# Mount a zealot gun turret on each Turret* marker (only the Shepherd carries
	# them; the censer/cross/rebuker/spear hulls have none, so this is a no-op).
	ZealotTurret.mount_all(self)


func _process(delta: float) -> void:
	super._process(delta)   # movement + offscreen + cycle
	if _dying or _cycling or not has_muzzles():
		return
	if not _on_playfield() or not Zones.in_engagement(position.y):
		return   # only broadside inside the firing band
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	_fire_t = FIRE_INTERVAL
	var pos: Vector2 = next_muzzle_pos()   # cycles Muzzle* in name order (rolls the hull)
	var b = BULLET.instantiate()
	b.variant = SHOT
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	world.add_child(b)
	if b.has_method("start"):
		b.start(pos, Vector2(0, 1))
	MuzzleFx.play_enemy(pos, Vector2(0, 1), world)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()
