extends RefCounted
class_name EnemyManifest

# Hardcoded enemy list for dev tools. `DirAccess.list_dir_begin` on res:// is
# unreliable in exported builds (it returns nothing on web), so the
# Shipyard and Movement Test tools read from this manifest instead of
# walking the filesystem at runtime.
#
# When adding a new enemy .tscn, append it here.
const ENEMIES: Array = [
	"res://scenes/enemies/bosses/boss.tscn",
	"res://scenes/enemies/bosses/boss_reaver.tscn",
	"res://scenes/enemies/bosses/boss_sentinel.tscn",
	"res://scenes/enemies/bosses/boss_howler.tscn",
	"res://scenes/enemies/bosses/boss_voidmaw.tscn",
	"res://scenes/enemies/bosses/boss_spinwright.tscn",
	"res://scenes/enemies/bosses/boss_conductor.tscn",
	"res://scenes/enemies/enemy_asteroid.tscn",
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn",
	"res://scenes/enemies/core/enemy_crystal.tscn",
	"res://scenes/enemies/core/enemy_cutter.tscn",
	"res://scenes/enemies/factions/privateer/enemy_dart.tscn",
	"res://scenes/enemies/core/enemy_drifter.tscn",
	"res://scenes/enemies/core/enemy_spitter.tscn",
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn",
	"res://scenes/enemies/core/enemy_hover.tscn",
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn",
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn",
	"res://scenes/enemies/enemy_mine.tscn",
	"res://scenes/enemies/enemy_mine_gravity.tscn",
	"res://scenes/enemies/enemy_mine_shield.tscn",
	"res://scenes/enemies/enemy_mine_smart.tscn",
	"res://scenes/enemies/enemy_mine_armored.tscn",
	"res://scenes/enemies/enemy_mine_tether.tscn",
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn",
	"res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn",
	"res://scenes/enemies/core/enemy_weaver.tscn",
]


const Factions = preload("res://scripts/levels/factions.gd")


static func paths() -> Array:
	return ENEMIES.duplicate()


# The FULL dev-tool enemy roster: the curated manifest UNION every faction-tagged enemy
# (Factions.ENEMY_TAGS), deduped + sorted. Faction units like the zealots are tagged there even
# when they're NOT in the hardcoded manifest or the production wave roll, so this is the canonical
# "show everything" list every enemy-listing dev tool should pull from — keeping them from drifting
# out of sync as new units land (Roman 2026-06-17). Bosses are excluded by default (bespoke tuning).
static func all_enemies(include_bosses: bool = false) -> Array:
	var seen := {}
	var out := []
	for src in [ENEMIES, Factions.ENEMY_TAGS.keys()]:
		for p in src:
			var s := String(p)
			if not include_bosses and s.to_lower().contains("boss"):
				continue
			if not seen.has(s):
				seen[s] = true
				out.append(s)
	out.sort()
	return out
