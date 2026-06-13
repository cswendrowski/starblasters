extends Resource

# Base class for enemy shoot patterns. Subclasses override `fire(enemy)`
# and call `_spawn_bullet(enemy, dir)` (or the multi-shot helper) for
# each shot they want to emit. The helper routes through one central
# spawn path so direction normalization, parent-of-bullet, and target
# group tagging stay consistent.
#
# Refactored 2026-05-17 alongside the BaseBullet consolidation. Older
# patterns hand-rolled the bullet spawn, the aim-at-player lookup, and
# the "spaced burst" timing with recursive awaits.

const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
const Clarity = preload("res://scripts/clarity.gd")
const BulletCatalog = preload("res://scripts/projectiles/bullet_catalog.gd")
# Ceiling on an enemy bullet's final damage after weapon multipliers (faction +
# sector compound via *=). Guard rail so a late-sector + 'armed' + future damage
# faction can't stack into a one-shot. Heaviest base today (heavy_slug=2) × armed
# (1.3) = ~3, so 4 leaves headroom without capping existing content.
const ENEMY_BULLET_DAMAGE_CAP := 4

@export var bullet_scene: PackedScene

# Per-pattern fire pacing. -1 means "don't override the enemy's
# fire_interval_min / fire_interval_max defaults"; positive values let
# the pattern claim its own rhythm (e.g. a heavy spread that needs more
# cooldown than the enemy's default cadence). The wave's
# fire_interval_min/max override still wins over this.
@export var fire_interval_min: float = -1.0
@export var fire_interval_max: float = -1.0

# Projectile-movement axis (M6a.2) — drive homing/wobble on every bullet this
# pattern spawns, INDEPENDENT of the payload variant's visuals. >0 overrides the
# variant's seeded movement (the variant is the default; the firing layer wins).
# This is where the "movement is the firing layer's job" decision lives: a plasma
# orb wobbles because its WEAPON says so, not because the bullet .tres bakes it.
# Faction/sector multipliers scale these. Inherited by Weapon + all subclasses.
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0

# Absolute per-pattern bullet speed (px/s), authored on the 1–8 px/f rung scale
# (60–480). -1 = "leave the payload variant's speed alone". When >0 it REPLACES
# the variant's baseline at spawn, BEFORE the enemy's faction/sector
# bullet_speed_mult compounds — so e.g. an aimed shot can sit at 300 instead of
# the variant's default 200 without authoring a whole new BulletVariant. Clamped
# to the clarity ceiling so a high rung can't strobe. (TODO: cheapest path before
# the full bullet-library speed pass.)
@export var bullet_speed: float = -1.0


func fire(_enemy) -> void:
	pass


# Stamp the movement axis onto a freshly spawned bullet. Only overrides when the
# pattern specifies a value (>0), so a payload variant's own movement is preserved
# when the pattern leaves the axis at 0.
func _apply_axis(b) -> void:
	if b == null:
		return
	if homing_rate > 0.0 and "homing_rate" in b:
		b.homing_rate = homing_rate
	if wobble_amplitude > 0.0 and "wobble_amplitude" in b:
		b.wobble_amplitude = wobble_amplitude
		b.wobble_frequency = wobble_frequency


# Spawn one bullet at the enemy with the given direction. Caller owns
# `dir` — it should be a unit vector pointing where the shot goes. The
# bullet's `target_group` is left at the scene's default ("player" for
# enemy_bullet.tscn) so this helper does not need to set it.
# Optional `bv` (BulletVariant) is applied before start() so the variant
# can override speed, damage, hitbox, and visuals at spawn time.
func _spawn_bullet(enemy, dir: Vector2, bv = null, spawn_override = null):
	# Resolve the payload's canonical per-bullet scene (weapons spec "Index: Enemy
	# Projectiles"): a variant with an indexed scene spawns THAT scene (its own
	# sprite/shader/hitbox); otherwise fall back to this pattern's bullet_scene.
	var scene: PackedScene = bullet_scene
	if bv != null:
		var mapped: PackedScene = BulletCatalog.scene_for(bv)
		if mapped != null:
			scene = mapped
	if scene == null:
		return null
	var b = scene.instantiate()
	if bv != null and "variant" in b:
		b.variant = bv
	# Spawn into the enemy's OWN container (its parent) rather than the window root, so bullets
	# share the enemy's coordinate space and survive its queue_free. In combat that's the main
	# scene (identical to the old root); in a SubViewport bench/hangar it's the preview world,
	# which keeps bullets in the playfield instead of the window's top-left corner.
	var bullet_parent: Node = enemy.get_parent()
	if bullet_parent == null:
		bullet_parent = enemy.get_tree().root
	bullet_parent.add_child(b)
	# Spawn at the next muzzle marker when the enemy has them (cycling
	# index alternates two-muzzle enemies); else the enemy center as before.
	# A pink muzzle flash plays at each muzzle in the fire direction. Un-
	# muzzled enemies (crystal spread, frigate burst) fall back to origin
	# and do NOT flash — only marker-equipped enemies get the flash.
	# `spawn_override` (a Vector2) pins the spawn to an exact world point — used by
	# pair_shot to fire one bullet from EACH muzzle in the same volley.
	var has_mz: bool = enemy.has_method("has_muzzles") and enemy.has_muzzles()
	var spawn_pos: Vector2
	if spawn_override != null:
		spawn_pos = spawn_override
	else:
		spawn_pos = enemy.next_muzzle_pos() if has_mz else enemy.global_position
	if b.has_method("start"):
		b.start(spawn_pos, dir)
	else:
		b.position = spawn_pos
	if has_mz or spawn_override != null:
		MuzzleFx.play_enemy(spawn_pos, dir, bullet_parent)
	# Drive the projectile-movement axis (homing/wobble) — applied after
	# _ready/_apply_variant so the pattern's axis overrides the variant's seed.
	_apply_axis(b)
	# Per-pattern absolute speed override (rung-authored). Replaces the variant's
	# baseline so the firing layer owns final speed; runs BEFORE the faction/sector
	# mult below so that scaling still compounds on top. Clamped to the ceiling.
	if bullet_speed > 0.0 and "speed" in b:
		b.speed = minf(bullet_speed, Clarity.ABS_MAX_SPEED)
	# Weapon multipliers (M6b faction/sector): scale the bullet's speed (clamped to the
	# clarity ceiling so a buff can't strobe) and damage. Applied after _apply_variant
	# set the baselines.
	if "bullet_speed_mult" in enemy and float(enemy.bullet_speed_mult) != 1.0 and "speed" in b:
		b.speed = minf(b.speed * float(enemy.bullet_speed_mult), Clarity.ABS_MAX_SPEED)
	if "bullet_damage_mult" in enemy and float(enemy.bullet_damage_mult) != 1.0 and "damage" in b:
		b.damage = clampi(int(round(float(b.damage) * float(enemy.bullet_damage_mult))), 1, ENEMY_BULLET_DAMAGE_CAP)
	return b


# Time-driven multi-shot helper. Replaces the old recursive `await` chain
# in burst_shot — fires `count` bullets spaced `interval` seconds apart,
# each in direction `dir`. Safe if the enemy dies mid-burst (the
# is_instance_valid gate stops further shots).
func _spawn_burst(enemy, dir: Vector2, count: int, interval: float, bv = null) -> void:
	if count <= 0 or bullet_scene == null:
		return
	_spawn_bullet(enemy, dir, bv)
	for i in range(1, count):
		await enemy.get_tree().create_timer(interval).timeout
		if not is_instance_valid(enemy):
			return
		_spawn_bullet(enemy, dir, bv)


# Resolve a unit vector aimed at the player's current position. Returns
# straight-down (Vector2(0, 1)) if the player can't be found — same
# safe default the legacy aimed_fire used.
func _aim_at_player(enemy, lead_factor: float = 0.0) -> Vector2:
	var tree = enemy.get_tree()
	if tree == null:
		return Vector2(0, 1)
	var player: Node = tree.get_first_node_in_group("player")
	if player == null:
		return Vector2(0, 1)
	var to_player: Vector2 = player.global_position - enemy.global_position
	if lead_factor > 0.0 and "velocity" in player:
		to_player += player.velocity * lead_factor
	if to_player.length() <= 0.001:
		return Vector2(0, 1)
	return to_player.normalized()
