extends Node
class_name EnemySfx

# Central enemy fire SFX (Roman audio pass, 2026-06-07). Mirrors WeaponSfx for
# the player side. Replaces the per-scene $EnemyShoot nodes (which played a
# single fixed legacy clip) with two randomized pools:
#   "enemy_blaster" — the new DEFAULT for every enemy weapon (8 clips)
#   "enemy_mg"      — weapons that fire the small-bullet or tracer payloads (6 clips)
#
# Classification is data-driven: a BulletVariant declares enemy_sfx_kind
# ("enemy_mg" on spread_pellet / aimed_sniper); everything else falls back to
# enemy_blaster. play_for(enemy) reads the enemy's live shoot pattern payload so
# the call sites (enemy_core, bespoke enemies, boss ShootTimer) stay one-liners.
#
# Each shot spawns its own transient AudioStreamPlayer2D parented under the scene
# root (NOT the enemy — enemies queue_free on death and would clip the sound),
# auto-freeing on `finished`. That gives natural polyphony for rapid fire.

const BLASTER_CLIPS := [
	preload("res://assets/audio/weapons/enemy/enemy_blaster_1.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_2.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_3.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_4.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_5.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_6.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_7.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_blaster_8.ogg"),
]
const MG_CLIPS := [
	preload("res://assets/audio/weapons/enemy/enemy_mg_1.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_mg_2.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_mg_3.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_mg_4.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_mg_5.ogg"),
	preload("res://assets/audio/weapons/enemy/enemy_mg_6.ogg"),
]

const DEFAULT_KIND := "enemy_blaster"
const VOLUME_DB: float = -6.0


# Resolve the BulletVariant a shoot pattern fires, regardless of which field
# holds it: M6 Weapon uses `payload`; the legacy single/aimed/spread/burst
# patterns use `bullet_variant`. Returns null if neither is set.
static func _variant_of(pattern) -> BulletVariant:
	if pattern == null:
		return null
	if "payload" in pattern and pattern.payload != null:
		return pattern.payload
	if "bullet_variant" in pattern and pattern.bullet_variant != null:
		return pattern.bullet_variant
	return null


# The sfx kind for an enemy's current weapon, derived from its payload variant.
static func kind_for(enemy) -> String:
	if enemy == null:
		return DEFAULT_KIND
	var pattern = enemy.shoot_pattern if "shoot_pattern" in enemy else null
	var bv := _variant_of(pattern)
	# Turrets / direct-fire enemies hold the variant on themselves, not on a
	# shoot_pattern.
	if bv == null and "bullet_variant" in enemy and enemy.bullet_variant != null:
		bv = enemy.bullet_variant
	if bv != null and "enemy_sfx_kind" in bv and bv.enemy_sfx_kind != "":
		return bv.enemy_sfx_kind
	return DEFAULT_KIND


# Per-volley fire sound for an enemy. Auto-classifies from the enemy's weapon
# payload unless `kind_override` is given (bespoke enemies that hand-roll their
# bullet and have no shoot_pattern pass the kind explicitly).
static func play_for(enemy, kind_override: String = "") -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var kind: String = kind_override if kind_override != "" else kind_for(enemy)
	var tree = enemy.get_tree()  # enemy is untyped → can't use := inference
	if tree == null:
		return
	var pos = enemy.global_position if enemy is Node2D else null
	play(tree.root, pos, kind)


static func play(parent: Node, world_pos, kind: String) -> void:
	if parent == null:
		return
	var pool: Array = []
	match kind:
		"enemy_blaster":
			pool = BLASTER_CLIPS
		"enemy_mg":
			pool = MG_CLIPS
		_:
			return
	if pool.is_empty():
		return
	var clip: AudioStream = pool[randi() % pool.size()]
	if clip == null:
		return
	if world_pos is Vector2:
		var p := AudioStreamPlayer2D.new()
		p.stream = clip
		p.volume_db = VOLUME_DB
		p.bus = "SFX"
		p.global_position = world_pos
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = clip
		p.volume_db = VOLUME_DB
		p.bus = "SFX"
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
