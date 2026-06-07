extends RefCounted
class_name EnemyManifest

# Hardcoded enemy list for dev tools. `DirAccess.list_dir_begin` on res:// is
# unreliable in exported builds (it returns nothing on web), so the
# Shipyard and Movement Test tools read from this manifest instead of
# walking the filesystem at runtime.
#
# When adding a new enemy .tscn, append it here.
const ENEMIES: Array = [
	"res://scenes/enemies/boss.tscn",
	"res://scenes/enemies/boss_reaver.tscn",
	"res://scenes/enemies/boss_sentinel.tscn",
	"res://scenes/enemies/boss_howler.tscn",
	"res://scenes/enemies/boss_voidmaw.tscn",
	"res://scenes/enemies/boss_spinwright.tscn",
	"res://scenes/enemies/boss_conductor.tscn",
	"res://scenes/enemies/enemy_asteroid.tscn",
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn",
	"res://scenes/enemies/core/enemy_crystal.tscn",
	"res://scenes/enemies/core/enemy_cutter.tscn",
	"res://scenes/enemies/core/enemy_dart.tscn",
	"res://scenes/enemies/core/enemy_drifter.tscn",
	"res://scenes/enemies/core/enemy_spitter.tscn",
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn",
	"res://scenes/enemies/core/enemy_hover.tscn",
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn",
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn",
	"res://scenes/enemies/enemy_mine.tscn",
	"res://scenes/enemies/enemy_mine_cluster.tscn",
	"res://scenes/enemies/enemy_mine_cluster_smart.tscn",
	"res://scenes/enemies/enemy_mine_shield.tscn",
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn",
	"res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn",
	"res://scenes/enemies/factions/corporate/enemy_strafer.tscn",
	"res://scenes/enemies/core/enemy_weaver.tscn",
]


static func paths() -> Array:
	return ENEMIES.duplicate()
