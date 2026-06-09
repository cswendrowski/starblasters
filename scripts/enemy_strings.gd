extends Object

# Enemy display strings (Roman 2026-06-07). Plain-text display NAME + codex flavor
# for every enemy, keyed by scene path. Placeholder name = the scene's stem (sans
# "enemy_"); placeholder codex = "TBD". Roman fills these in over time.
#
# Preload-referenced, NOT a class_name (headless class-cache safety, matching factions /
# beam_emitter / lane_traffic). Usage:
#   const EnemyStrings = preload("res://scripts/enemy_strings.gd")
#   EnemyStrings.display_name(scene_path)   # -> display name (derived fallback if unlisted)
#   EnemyStrings.codex_entry(scene_path)    # -> codex text ("TBD" default)

const STRINGS := {
	"res://scenes/enemies/boss.tscn": {"name": "boss", "codex": "TBD"},
	"res://scenes/enemies/boss_conductor.tscn": {"name": "boss_conductor", "codex": "TBD"},
	"res://scenes/enemies/boss_howler.tscn": {"name": "boss_howler", "codex": "TBD"},
	"res://scenes/enemies/boss_reaver.tscn": {"name": "boss_reaver", "codex": "TBD"},
	"res://scenes/enemies/boss_sentinel.tscn": {"name": "boss_sentinel", "codex": "TBD"},
	"res://scenes/enemies/boss_spinwright.tscn": {"name": "boss_spinwright", "codex": "TBD"},
	"res://scenes/enemies/boss_voidmaw.tscn": {"name": "boss_voidmaw", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_bomb_drone.tscn": {"name": "bomb_drone", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_bomber.tscn": {"name": "bomber", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"name": "cruiser", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_crystal.tscn": {"name": "crystal", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_cutter.tscn": {"name": "cutter", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_drifter.tscn": {"name": "drifter", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_hover.tscn": {"name": "hover", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_spitter.tscn": {"name": "spitter", "codex": "TBD"},
	"res://scenes/enemies/core/enemy_weaver.tscn": {"name": "weaver", "codex": "TBD"},
	"res://scenes/enemies/core/missile_cruiser.tscn": {"name": "missile_cruiser", "codex": "TBD"},
	"res://scenes/enemies/enemy_asteroid.tscn": {"name": "Asteroid", "codex": "TBD"},
	"res://scenes/enemies/enemy_beam_turret.tscn": {"name": "beam_turret", "codex": "TBD"},
	"res://scenes/enemies/enemy_bomblet.tscn": {"name": "Bomblet", "codex": "TBD"},
	"res://scenes/enemies/enemy_boss_drone.tscn": {"name": "boss_drone", "codex": "TBD"},
	"res://scenes/enemies/enemy_gun_turret.tscn": {"name": "gun_turret", "codex": "TBD"},
	"res://scenes/enemies/enemy_mine.tscn": {"name": "Mine", "codex": "TBD"},
	"res://scenes/enemies/enemy_mine_gravity.tscn": {"name": "Gravity Mine", "codex": "TBD"},
	"res://scenes/enemies/enemy_mine_shield.tscn": {"name": "Shielded Mine", "codex": "TBD"},
	"res://scenes/enemies/enemy_mine_smart.tscn": {"name": "Smart Mine", "codex": "TBD"},
	"res://scenes/enemies/enemy_mine_armored.tscn": {"name": "Armored Mine", "codex": "TBD"},
	"res://scenes/enemies/enemy_shield_pylon.tscn": {"name": "Shield Drone", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn": {"name": "bulwark", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_c_dart.tscn": {"name": "c_dart", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"name": "c_s_curve", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn": {"name": "c_s_drop", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn": {"name": "c_s_gray", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"name": "c_s_hold", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn": {"name": "drone_carrier", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn": {"name": "hunter_drone", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_sapper.tscn": {"name": "sapper", "codex": "TBD"},
	"res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn": {"name": "skirmisher", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_dart.tscn": {"name": "dart", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_gunship.tscn": {"name": "gunship", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn": {"name": "interceptor", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn": {"name": "minelayer", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"name": "p_m_cannon", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"name": "p_m_pulse", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn": {"name": "p_s_drop", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn": {"name": "p_s_gray", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn": {"name": "p_s_green", "codex": "TBD"},
	"res://scenes/enemies/factions/privateer/enemy_rocket.tscn": {"name": "rocket", "codex": "TBD"},
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn": {"name": "frigate", "codex": "TBD"},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"name": "s_m_plasma", "codex": "TBD"},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"name": "s_m_push", "codex": "TBD"},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"name": "s_s_hotrod", "codex": "TBD"},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"name": "s_s_rush", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"name": "beam_shooter", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn": {"name": "beamer_lock", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"name": "beamer_tracker", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_burner.tscn": {"name": "burner", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_firecore_cruiser.tscn": {"name": "firecore_cruiser", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_firecore_drone.tscn": {"name": "firecore_drone", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"name": "z_s_manta", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_z_s_retro.tscn": {"name": "z_s_retro", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_z_s_run.tscn": {"name": "z_s_run", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"name": "z_s_shiv", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"name": "z_s_sword", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/firecore_core.tscn": {"name": "firecore_core", "codex": "TBD"},
	"res://scenes/enemies/factions/zealot/firecore_hazard.tscn": {"name": "firecore_hazard", "codex": "TBD"},
	"res://scenes/enemies/tether_mine.tscn": {"name": "Tether Mine", "codex": "TBD"},
}


# Display name for a scene path. Falls back to a derived name (file stem, sans
# "enemy_", underscores -> spaces) for any scene not in the table.
static func display_name(scene_path: String) -> String:
	var e: Variant = STRINGS.get(scene_path, null)
	if e != null and str(e.get("name", "")) != "":
		return str(e["name"])
	return _derive(scene_path)


# Codex flavor text for a scene path ("TBD" default for unlisted / unfilled).
static func codex_entry(scene_path: String) -> String:
	var e: Variant = STRINGS.get(scene_path, null)
	if e != null:
		return str(e.get("codex", "TBD"))
	return "TBD"


static func _derive(scene_path: String) -> String:
	var stem: String = scene_path.get_file().get_basename()
	if stem.begins_with("enemy_"):
		stem = stem.substr(6)
	return stem.replace("_", " ")
