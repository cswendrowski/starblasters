class_name OrbitComponent
extends EnemyComponent

# OrbitComponent (2026-06-19) — N rings of payloads orbiting the host, RELEASED on death. The
# configurable generalization of the two bespoke "orbiting payload" enemies:
#   firecore_drone — concentric rings of bullet SHELLS that fly outward as real bullets on death.
#   gravity_mine   — a ring of real, hittable BOMBLETS, freed on death with their orbit velocity.
# "Set the rings + what's in them." Add to any enemy via the `components` slot (roster / bench).
#
# Two MODES:
#   VISUAL — orbiting Sprite2D shells (CHILDREN of the host; not hittable). On death each shell
#            spawns a projectile (the ring's bullet variant) flying radially OUTWARD at release_speed.
#   LIVE   — orbiting real payload SCENES (world SIBLINGS; hittable + killable). The host drives the
#            orbit; on death the survivors are RELEASED with the host drift + their tangential orbit
#            velocity. The payload scene must expose set_orbiting(bool) + release(Vector2).
#
# Per-instance state (_orbs) lives here — components are duplicate()'d per spawn (the resource rule).

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const EnemyBulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
const DEFAULT_ORB_TEX = preload("res://graphics/projectiles/enemy_bullet.png")

enum Mode { VISUAL, LIVE }

@export var mode: int = Mode.VISUAL
# Each ring: { radius:float, count:int, speed:float (rad/s; sign = spin direction),
#   variant:Resource (BulletVariant — VISUAL release / orb tint), scene:PackedScene (LIVE payload),
#   tex:Texture2D (VISUAL orb sprite; default = enemy_bullet.png), scale:float, color:Color }.
@export var rings: Array = []
@export var release_speed: float = 140.0   # VISUAL: outward speed of released projectiles (px/s)
@export var host_drift: float = 0.0        # LIVE: host downward drift inherited on release (px/s)
@export var release_sfx: String = "enemy_blaster"

var _orbs: Array = []   # [{node, radius, angle, omega, ring}]
var _t: float = 0.0
var _built: bool = false


func on_start(enemy) -> void:
	# Build ONCE per instance (on_start re-runs on parallax recycle; the orbits persist).
	if _built:
		return
	_built = true
	for ri in rings.size():
		var ring: Dictionary = rings[ri]
		var radius: float = float(ring.get("radius", 16.0))
		var count: int = int(ring.get("count", 6))
		var omega: float = float(ring.get("speed", 1.6))
		var phase0: float = randf() * TAU
		for i in count:
			var angle: float = phase0 + TAU * float(i) / float(maxi(1, count))
			var node = _make_orb(enemy, ring, angle, radius)
			if node != null:
				_orbs.append({"node": node, "radius": radius, "angle": angle, "omega": omega, "ring": ri})


func _make_orb(enemy, ring: Dictionary, angle: float, radius: float):
	var scale: float = float(ring.get("scale", 1.0))
	if mode == Mode.LIVE:
		var scene: PackedScene = ring.get("scene", null)
		if scene == null:
			return null
		var b = scene.instantiate()
		# Real payloads ride as world SIBLINGS so they survive the host's free; the host drives pos.
		var parent: Node = enemy.get_parent()
		if parent == null:
			parent = enemy
		parent.add_child(b)
		if b.has_method("set_orbiting"):
			b.set_orbiting(true)
		if b is Node2D:
			(b as Node2D).global_position = enemy.global_position + Vector2(cos(angle), sin(angle)) * radius
		return b
	# VISUAL: a sprite shell child of the host.
	var spr := Sprite2D.new()
	var tex: Texture2D = ring.get("tex", null)
	if tex == null:
		tex = DEFAULT_ORB_TEX
	spr.texture = tex
	spr.hframes = 3
	spr.frame = randi() % 3
	spr.z_index = 1
	if scale != 1.0:
		spr.scale = Vector2(scale, scale)
	if ring.has("color"):
		spr.modulate = ring["color"]
	spr.position = Vector2(cos(angle), sin(angle)) * radius
	enemy.add_child(spr)
	return spr


func on_process(enemy, delta: float) -> void:
	if _orbs.is_empty():
		return
	_t += delta
	var live: Array = []
	for orb in _orbs:
		var node = orb["node"]
		if node == null or not is_instance_valid(node) or ("_dying" in node and node._dying):
			continue
		var a: float = float(orb["angle"]) + _t * float(orb["omega"])
		var off: Vector2 = Vector2(cos(a), sin(a)) * float(orb["radius"])
		if mode == Mode.LIVE:
			node.global_position = enemy.global_position + off
		else:
			node.position = off
		live.append(orb)
	_orbs = live


func on_death(enemy) -> void:
	_release(enemy)


func on_leave(enemy) -> void:
	# Recycled / escaped — don't strand LIVE payloads frozen in space.
	_release(enemy)


func _release(enemy) -> void:
	if _orbs.is_empty():
		return
	if mode == Mode.LIVE:
		_release_live()
	else:
		_release_visual(enemy)
	_orbs = []


func _release_live() -> void:
	var drift := Vector2(0.0, host_drift)
	for orb in _orbs:
		var node = orb["node"]
		if node == null or not is_instance_valid(node) or not node.has_method("release"):
			continue
		var a: float = float(orb["angle"]) + _t * float(orb["omega"])
		# Tangent direction × speed (omega × radius), preserving spin direction.
		var tangential: Vector2 = Vector2(-sin(a), cos(a)) * float(orb["omega"]) * float(orb["radius"])
		node.release(drift + tangential)


func _release_visual(enemy) -> void:
	var tree: SceneTree = enemy.get_tree()
	if tree == null:
		return
	var world: Node = BulletWorld.resolve(enemy, tree.root)
	if world == null:
		world = tree.root
	var origin: Vector2 = enemy.global_position
	for orb in _orbs:
		var node = orb["node"]
		if node == null or not is_instance_valid(node):
			continue
		var wpos: Vector2 = (node as Node2D).global_position
		var dir: Vector2 = wpos - origin
		dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0, 1)
		var ring: Dictionary = rings[int(orb["ring"])] if int(orb["ring"]) < rings.size() else {}
		var b = EnemyBulletScene.instantiate()
		var variant = ring.get("variant", null)
		if variant != null:
			b.variant = variant
		world.add_child(b)
		if b.has_method("start"):
			b.start(wpos, dir)
		if "speed" in b:
			b.speed = release_speed
		var scale: float = float(ring.get("scale", 1.0))
		if scale != 1.0 and b is Node2D:
			(b as Node2D).scale = Vector2(scale, scale)
		(node as Node2D).queue_free()
	if release_sfx != "":
		EnemySfxC.play_for(enemy, release_sfx)
