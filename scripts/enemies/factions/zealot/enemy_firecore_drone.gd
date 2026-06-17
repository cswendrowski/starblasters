extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyFirecoreDrone

# Firecore Drone (Roman, 2026-05-31). Small + tough drone that descends
# slowly. Instead of shooting, it surrounds itself with 1-4 concentric rings
# of inert "bullet" visuals that orbit at alternating directions/speeds.
# Killing the drone DETACHES every ring bullet — each becomes a live
# enemy_bullet flying radially OUTWARD from the drone, so death releases
# expanding concentric bullet waves the player must dodge.
#
# Shot variation (Roman 2026-06-07, "bloom" re-skin): rings alternate between
# STANDARD and SMALL bullets — odd-indexed rings render + release at SMALL_SCALE
# (smaller visual AND hitbox, since scaling the Area2D scales its collision too),
# so the concentric waves read as mixed-calibre instead of uniform.
#
# Bespoke self-driving enemy (no movement/shoot Resource slots) — extends
# enemy_base.gd directly like enemy_firecore_cruiser. Rings are built in
# _ready() from `ring_count`, so anything configuring ring_count (capture
# tool, director's ring_count_override) MUST set it before add_child().

# --- KNOBS for Roman to tune ------------------------------------------------
# Number of concentric rings (clamped 1-4). More rings = denser local
# bullet-flower AND a bigger release on death.
@export var ring_count: int = 2
# Inner ring radius (px) and per-ring radius step (px). Rings sit at
# RING_RADIUS_BASE, +RING_RADIUS_STEP, +2*step, ...
const RING_RADIUS_BASE: float = 14.0
const RING_RADIUS_STEP: float = 10.0
# Bullet count of the innermost ring; each outer ring adds RING_BULLET_STEP.
const RING_BULLET_BASE: int = 6
const RING_BULLET_STEP: int = 4
# Base angular speed magnitude (rad/s) of the innermost ring; outer rings
# scale by RING_SPEED_FALLOFF^ring so each ring spins at a different speed.
# Sign alternates per ring (opposite spin directions).
const RING_SPEED_BASE: float = 1.6
const RING_SPEED_FALLOFF: float = 0.7
# Released-bullet speed when the drone dies (px/s). Dodgeable wave.
const RELEASE_SPEED: float = 140.0
# Slow constant downward descent (px/s).
const DESCENT_SPEED: float = 40.0
# Visual+hitbox scale for the SMALL bullet rings (odd ring indices).
const SMALL_SCALE: float = 0.6
# ---------------------------------------------------------------------------

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const RingBulletTex = preload("res://graphics/projectiles/enemy_bullet.png")
const EnemyBulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const BV_Basic = preload("res://data/bullets/basic.tres")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")

# One orbiting visual: its Sprite2D node, its ring index, base angle (phase),
# orbit radius, and signed angular speed.
var _ring_bullets: Array = []   # Array of Dictionary {node, radius, angle, speed}
var _t: float = 0.0


func _ready() -> void:
	# Small + tough. Stats BEFORE super._ready() (boss 1-HP-bug convention).
	max_health = 10
	bounty_value = 25
	# auto_rotate=false: the base would rotate the whole Area2D toward its
	# velocity, dragging the ring-bullet children with it and fighting the
	# orbit math. Also skips the damage-shader/shadow path cleanly.
	auto_rotate = false
	display_scale = 1.0
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	super._ready()

	ring_count = clampi(ring_count, 1, 4)
	_build_rings()


# Build `ring_count` concentric rings of inert bullet visuals as children so
# they ride along with the drone. Repositioned every frame in _process.
func _build_rings() -> void:
	for ring in range(ring_count):
		var radius: float = RING_RADIUS_BASE + RING_RADIUS_STEP * float(ring)
		var bullet_count: int = RING_BULLET_BASE + RING_BULLET_STEP * ring
		# Alternate spin direction per ring; magnitude falls off outward so
		# each ring spins at a visibly different speed.
		var spin_sign: float = -1.0 if (ring % 2 == 1) else 1.0
		var speed: float = RING_SPEED_BASE * pow(RING_SPEED_FALLOFF, float(ring)) * spin_sign
		var phase_base: float = randf() * TAU
		# Alternate ring calibre: odd rings are SMALL (standard / small variation).
		var small: bool = (ring % 2 == 1)
		for i in range(bullet_count):
			var angle: float = phase_base + TAU * (float(i) / float(bullet_count))
			var spr := Sprite2D.new()
			spr.texture = RingBulletTex
			# enemy_bullet.png is a 3-frame strip; show one frame via hframes.
			spr.hframes = 3
			spr.frame = randi() % 3
			spr.z_index = 1
			if small:
				spr.scale = Vector2(SMALL_SCALE, SMALL_SCALE)
			spr.position = Vector2.from_angle(angle) * radius
			add_child(spr)
			_ring_bullets.append({
				"node": spr,
				"radius": radius,
				"angle": angle,
				"speed": speed,
				"small": small,
			})


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	# Slow constant descent. Clamp X into the playfield band.
	global_position.y += DESCENT_SPEED * delta
	global_position.x = clampf(global_position.x, Playfield.X_MIN, Playfield.X_MAX)

	# Spin every ring bullet around the drone (local space — children ride
	# the drone's global_position automatically).
	for rb in _ring_bullets:
		var node: Node2D = rb["node"]
		if not is_instance_valid(node):
			continue
		var a: float = rb["angle"] + _t * rb["speed"]
		node.position = Vector2.from_angle(a) * rb["radius"]

	# Offscreen cleanup (auto_rotate=false makes the rotation step a no-op).
	super._process(delta)


# DETACH ON DEATH. Each inert ring bullet spawns a real enemy_bullet at its
# current WORLD position, heading radially OUTWARD from the drone, preserving
# the ring's angular spacing → clean expanding bullet rings. Parent to the
# tree root so they survive the drone's queue_free.
func explode() -> void:
	if _dying:
		return
	_release_rings()
	# Always use ball explosion for the drone (it's a firecore carrier)
	explosion_variant = "ball"
	super.explode()


func _release_rings() -> void:
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	var drone_world: Vector2 = global_position
	for rb in _ring_bullets:
		var node: Node2D = rb["node"]
		if not is_instance_valid(node):
			continue
		var bullet_world: Vector2 = node.global_position
		var dir: Vector2 = (bullet_world - drone_world)
		if dir == Vector2.ZERO:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var b = EnemyBulletScene.instantiate()
		# variant must be set BEFORE add_child — base_bullet applies it in
		# _ready(). Then start() positions + orients, then we override speed
		# (basic.tres ships at 220; RELEASE_SPEED keeps the wave dodgeable).
		b.variant = BV_Basic
		world.add_child(b)
		if b.has_method("start"):
			b.start(bullet_world, dir)
		else:
			b.global_position = bullet_world
		if "speed" in b:
			b.speed = RELEASE_SPEED
		# Small rings release small bullets — scale the Area2D so the visual AND
		# the collision shrink together (set after start(), which sets pos/rot).
		if rb.get("small", false):
			b.scale = Vector2(SMALL_SCALE, SMALL_SCALE)
		node.queue_free()
	# One blaster report per ring release (basic bullets), not per pellet.
	if not _ring_bullets.is_empty():
		EnemySfxC.play_for(self, "enemy_blaster")
	_ring_bullets.clear()
