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

@export var bullet_scene: PackedScene

# Per-pattern fire pacing. -1 means "don't override the enemy's
# fire_interval_min / fire_interval_max defaults"; positive values let
# the pattern claim its own rhythm (e.g. a heavy spread that needs more
# cooldown than the enemy's default cadence). The wave's
# fire_interval_min/max override still wins over this.
@export var fire_interval_min: float = -1.0
@export var fire_interval_max: float = -1.0


func fire(_enemy) -> void:
	pass


# Spawn one bullet at the enemy with the given direction. Caller owns
# `dir` — it should be a unit vector pointing where the shot goes. The
# bullet's `target_group` is left at the scene's default ("player" for
# enemy_bullet.tscn) so this helper does not need to set it.
# Optional `bv` (BulletVariant) is applied before start() so the variant
# can override speed, damage, hitbox, and visuals at spawn time.
func _spawn_bullet(enemy, dir: Vector2, bv = null):
	if bullet_scene == null:
		return null
	var b = bullet_scene.instantiate()
	if bv != null and "variant" in b:
		b.variant = bv
	enemy.get_tree().root.add_child(b)
	# Spawn at the next muzzle marker when the enemy has them (cycling
	# index alternates two-muzzle enemies); else the enemy center as before.
	# A pink muzzle flash plays at each muzzle in the fire direction. Un-
	# muzzled enemies (crystal spread, frigate burst) fall back to origin
	# and do NOT flash — only marker-equipped enemies get the flash.
	var has_mz: bool = enemy.has_method("has_muzzles") and enemy.has_muzzles()
	var spawn_pos: Vector2 = enemy.next_muzzle_pos() if has_mz else enemy.global_position
	if b.has_method("start"):
		b.start(spawn_pos, dir)
	else:
		b.position = spawn_pos
	if has_mz:
		MuzzleFx.play_enemy(spawn_pos, dir, enemy.get_tree().root)
	# Return the spawned bullet so the firing layer (a Weapon) can drive the
	# projectile-movement axis (homing/wobble) on it after _ready/_apply_variant.
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
