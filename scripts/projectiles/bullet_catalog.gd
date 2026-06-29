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
const FactionsC  = preload("res://scripts/levels/factions.gd")
# Zealot faction projectiles (Roman 2026-06-16) — each maps to its own freestanding scene.
const _V_ZBALL   = preload("res://data/bullets/zealot_ball.tres")
const _V_ZBOLT   = preload("res://data/bullets/zealot_bolt.tres")
const _V_ZLASER  = preload("res://data/bullets/zealot_laser.tres")
const _V_ZWAVE   = preload("res://data/bullets/zealot_wave.tres")
# Privateer faction projectiles (2026-06-20) — stat-clones of the zealot set with green textures.
const _V_PBALL   = preload("res://data/bullets/privateer_ball.tres")
const _V_PBOLT   = preload("res://data/bullets/privateer_bolt.tres")
const _V_PLASER  = preload("res://data/bullets/privateer_laser.tres")
const _V_PWAVE   = preload("res://data/bullets/privateer_wave.tres")

const _S_BASIC   = preload("res://scenes/projectiles/enemy_bullet.tscn")
const _S_SMALL   = preload("res://scenes/projectiles/enemy_bullet_small.tscn")
const _S_LARGE   = preload("res://scenes/projectiles/enemy_bullet_large.tscn")
const _S_WAVE    = preload("res://scenes/projectiles/enemy_bullet_wave.tscn")
const _S_LASER   = preload("res://scenes/projectiles/enemy_bullet_laser.tscn")
const _S_CANNON  = preload("res://scenes/projectiles/enemy_bullet_cannon.tscn")
const _S_DIAMOND = preload("res://scenes/projectiles/enemy_bullet_diamond.tscn")
const _S_TRACER  = preload("res://scenes/projectiles/enemy_bullet_tracer.tscn")
const _S_ZBALL   = preload("res://scenes/projectiles/zealot/zealot_bullet_ball.tscn")
const _S_ZBOLT   = preload("res://scenes/projectiles/zealot/zealot_bullet_bolt.tscn")
const _S_ZLASER  = preload("res://scenes/projectiles/zealot/zealot_bullet_laser.tscn")
const _S_ZWAVE   = preload("res://scenes/projectiles/zealot/zealot_bullet_wave.tscn")
const _S_PBALL   = preload("res://scenes/projectiles/privateer/privateer_bullet_ball.tscn")
const _S_PBOLT   = preload("res://scenes/projectiles/privateer/privateer_bullet_bolt.tscn")
const _S_PLASER  = preload("res://scenes/projectiles/privateer/privateer_bullet_laser.tscn")
const _S_PWAVE   = preload("res://scenes/projectiles/privateer/privateer_bullet_wave.tscn")

static var _map: Dictionary = {}
# Bullet-appearance families (2026-06-20): logical archetype -> {faction Id -> variant}. A
# family-tagged variant is swapped for the active faction's same-family variant at fire time
# (BulletCatalog.faction_variant), so a universal enemy's shots take the level faction's style.
# Factions with no entry fall back to the authored variant (corpo/supremacy until their sets exist).
static var _family: Dictionary = {}


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
	_map[_V_ZBALL]   = _S_ZBALL
	_map[_V_ZBOLT]   = _S_ZBOLT
	_map[_V_ZLASER]  = _S_ZLASER
	_map[_V_ZWAVE]   = _S_ZWAVE
	_map[_V_PBALL]   = _S_PBALL
	_map[_V_PBOLT]   = _S_PBOLT
	_map[_V_PLASER]  = _S_PLASER
	_map[_V_PWAVE]   = _S_PWAVE
	var Z: int = FactionsC.Id.ZEALOT
	var P: int = FactionsC.Id.PRIVATEER
	# Supremacy + Corporate have no bespoke bullet art yet, so they REUSE the zealot/privateer styled
	# clones for now (Roman 2026-06-29): Supremacy borrows the zealot look, Corporate the privateer
	# look. Swap these to dedicated S/C variants once that art exists. Every family covers all 4
	# factions so a generic "ball"/"bolt"/"laser"/"wave" payload always resolves to a styled bullet.
	var S: int = FactionsC.Id.SUPREMACY
	var C: int = FactionsC.Id.CORPORATE
	_family["ball"]  = {Z: _V_ZBALL,  P: _V_PBALL,  S: _V_ZBALL,  C: _V_PBALL}
	_family["bolt"]  = {Z: _V_ZBOLT,  P: _V_PBOLT,  S: _V_ZBOLT,  C: _V_PBOLT}
	_family["laser"] = {Z: _V_ZLASER, P: _V_PLASER, S: _V_ZLASER, C: _V_PLASER}
	_family["wave"]  = {Z: _V_ZWAVE,  P: _V_PWAVE,  S: _V_ZWAVE,  C: _V_PWAVE}


# The canonical per-bullet scene for a BulletVariant, or null if the variant has no
# indexed scene (caller should fall back to its own bullet_scene).
static func scene_for(variant) -> PackedScene:
	if variant == null:
		return null
	_ensure()
	return _map.get(variant, null)


# Resolve a bullet variant to the active faction's same-family variant (appearance facet). A
# family-tagged variant (ball/bolt/laser/wave) becomes the faction's styled clone; an untagged
# variant, an unknown faction (-1), or a faction with no entry for that family returns `variant`
# unchanged (the authored bullet is always the fallback). Stats are clones, so this is appearance-only.
static func faction_variant(variant, faction: int):
	if variant == null or faction < 0:
		return variant
	var fam: StringName = variant.family if ("family" in variant) else &""
	if String(fam) == "":
		return variant
	_ensure()
	var byf: Variant = _family.get(String(fam), null)
	if byf == null:
		return variant
	return byf.get(faction, variant)
