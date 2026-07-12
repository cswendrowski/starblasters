extends Object

# Canonical per-bullet SCENE for each BulletVariant payload (Roman 2026-06-08, weapons spec "Index:
# Enemy Projectiles"), plus the faction frame-reskin resolver. Every live enemy bullet variant carries
# its OWN bullet_scene (a projectile_<type> 4-frame sheet); the firing layer resolves that scene here and
# `faction_variant` selects the faction's frame on it.
#
# The old per-type indexed _map (enemy_bullet_*.tscn) + the per-faction _family swap (separate
# zealot_*/privateer_* .tres per faction) were RETIRED 2026-07-07 with the multi-faction bullet
# consolidation — every payload is now a frame-reskin family, so those lookups are gone.
#
# Preload-referenced (NOT class_name) for headless class-cache safety, mirroring factions.gd.

const FactionsC = preload("res://scripts/levels/factions.gd")


# The canonical per-bullet scene for a BulletVariant: its own bullet_scene (the frame-reskin families),
# or null if it carries none (the caller then keeps its own bullet_scene).
static func scene_for(variant) -> PackedScene:
	if variant == null:
		return null
	if "bullet_scene" in variant and variant.bullet_scene != null:
		return variant.bullet_scene
	return null


# Faction Id -> sprite-sheet frame on the projectile_<type> scenes. Single source of truth is
# Factions.WEAPON_COLORS (frame per named colour) + FACTION_WEAPON_COLOR (colour per faction), so the
# frame stays in lockstep with the muzzle/glow colours. -1 = no frame for this faction.
static func _frame_for_faction(faction: int) -> int:
	return FactionsC.weapon_frame(faction)


# Cache of per-(variant, faction) frame-reskin clones, so the duplicate is built once not per bullet.
static var _skin_cache: Dictionary = {}


# Resolve a bullet variant to the active faction's frame on its projectile_<type> sheet (appearance
# facet). A variant carrying its own scene selects the faction's frame on a cached clone; an untagged
# variant, an unknown faction (-1), or a faction with no frame returns `variant` unchanged. Stats are
# clones, so this is appearance-only.
static func faction_variant(variant, faction: int):
	if variant == null or faction < 0:
		return variant
	if "bullet_scene" in variant and variant.bullet_scene != null:
		var fr: int = _frame_for_faction(faction)
		if fr < 0:
			return variant
		var key: String = "%d:%d" % [variant.get_instance_id(), faction]
		if not _skin_cache.has(key):
			var clone = variant.duplicate()
			clone.frame = fr
			_skin_cache[key] = clone
		var out = _skin_cache[key]
		# Bullet-impact tint tracks the faction muzzle/glow colour (SSOT: Factions.muzzle_glow_color) so an
		# enemy's hit flash + sparks match its muzzle flash + bolt. Set EVERY call (not just on the cache
		# miss) so a hot-reload or a colour retune can't leave a stale clone with the old white impact
		# (the "faction-coloured bolt but white impact" bug, Roman 2026-07-09).
		if "impact_color" in out:
			out.impact_color = FactionsC.muzzle_glow_color(faction)
		return out
	return variant
