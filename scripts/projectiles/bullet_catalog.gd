extends Object

# Canonical per-bullet SCENE for each BulletVariant payload (Roman 2026-06-08, weapons
# spec "Index: Enemy Projectiles"). The firing layer resolves a variant to ITS OWN scene
# here, so every enemy bullet spawns from the indexed scene — with that scene's authored
# sprite / shader / hitbox — instead of the shared enemy_bullet.tscn shell + a runtime
# sprite-swap. This is what makes the Index the single source of projectile art.
#
# Preload-referenced (NOT class_name) for headless class-cache safety, mirroring
# factions.gd. Variants with no indexed scene (the drop_pellet / fast_pellet extras)
# return null, and the caller keeps its own bullet_scene.

const _V_BASIC   = preload("res://data/bullets/basic.tres")
const _V_SPREAD  = preload("res://data/bullets/spread_pellet.tres")
const _V_LARGE   = preload("res://data/bullets/heavy_slug.tres")
const _V_WAVE    = preload("res://data/bullets/plasma_orb.tres")
const _V_LASER   = preload("res://data/bullets/laser_bolt.tres")
const _V_CANNON  = preload("res://data/bullets/burst_round.tres")
const _V_DIAMOND = preload("res://data/bullets/tracker.tres")
const _V_TRACER  = preload("res://data/bullets/aimed_sniper.tres")

const _S_BASIC   = preload("res://scenes/projectiles/enemy_bullet.tscn")
const _S_SMALL   = preload("res://scenes/projectiles/enemy_bullet_small.tscn")
const _S_LARGE   = preload("res://scenes/projectiles/enemy_bullet_large.tscn")
const _S_WAVE    = preload("res://scenes/projectiles/enemy_bullet_wave.tscn")
const _S_LASER   = preload("res://scenes/projectiles/enemy_bullet_laser.tscn")
const _S_CANNON  = preload("res://scenes/projectiles/enemy_bullet_cannon.tscn")
const _S_DIAMOND = preload("res://scenes/projectiles/enemy_bullet_diamond.tscn")
const _S_TRACER  = preload("res://scenes/projectiles/enemy_bullet_tracer.tscn")

static var _map: Dictionary = {}


static func _ensure() -> void:
	if not _map.is_empty():
		return
	_map[_V_BASIC]   = _S_BASIC
	_map[_V_SPREAD]  = _S_SMALL
	_map[_V_LARGE]   = _S_LARGE
	_map[_V_WAVE]    = _S_WAVE
	_map[_V_LASER]   = _S_LASER
	_map[_V_CANNON]  = _S_CANNON
	_map[_V_DIAMOND] = _S_DIAMOND
	_map[_V_TRACER]  = _S_TRACER


# The canonical per-bullet scene for a BulletVariant, or null if the variant has no
# indexed scene (caller should fall back to its own bullet_scene).
static func scene_for(variant) -> PackedScene:
	if variant == null:
		return null
	_ensure()
	return _map.get(variant, null)
