extends Object

# Pattern eligibility (docs/pattern_eligibility_2026-06-08.md). Per enemy SCENE:
#   identity — its signature movement key (drives the enemy unless an entry opts into variety).
#   eligible — the movement keys it MAY be assigned (always includes identity).
#
# resolve(entry): a "vary": true entry gets a flat-random ELIGIBLE key; otherwise the MATRIX
# identity drives (so the eligibility tool actually controls each enemy's movement), falling
# back to the entry's own "movement" for scenes not in the matrix. Bespoke-movement enemies
# (bomber, beam-shooters, firecore_drone) are absent — they move via their own scripts.
#
# COMMITTED source of truth (ships in the pck). The Pattern Eligibility dev tool edits
# user://tuners/pattern_eligibility.json and EXPORTs back to this DATA const — production never
# reads user://. Preload-referenced, NOT a global class_name (headless-safe), mirroring
# factions.gd. Keys are the make_movement movement keys (see enemy_roster.make_movement).
# Remapped to the 2026-06-08 pattern set (straight_* by speed, skirmish/drift/hunt/side/lane_*).

# Exported from the Pattern Eligibility dev tool (user://tuners/pattern_eligibility.json),
# 2026-06-09. Strafer dropped (retired); "beam_sweep" renamed to "loiter_sweep".
const DATA := {
	"res://scenes/enemies/core/enemy_bomb_drone.tscn": {"identity": "straight_fast", "eligible": ["straight_fast", "straight_charge", "straight_medium", "straight_reflex", "hunt_beeline"]},
	"res://scenes/enemies/core/enemy_bomber.tscn": {"identity": "drift_mid", "eligible": ["drift_high", "drift_mid"]},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"identity": "loiter_high", "eligible": ["drift_high", "drift_mid", "loiter_high", "loiter_mid"]},
	"res://scenes/enemies/core/enemy_crystal.tscn": {"identity": "loiter_high", "eligible": ["loiter_high", "loiter_mid"]},
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn": {"identity": "drift_mid", "eligible": ["drift_mid", "drift_high"]},
	"res://scenes/enemies/factions/corporate/enemy_c_dart.tscn": {"identity": "straight_fast", "eligible": ["straight_fast", "straight_charge", "straight_reflex"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "lane_drift", "lane_shift", "lane_weave", "side_dive", "straight_charge", "straight_fast", "straight_medium"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn": {"identity": "straight_medium", "eligible": ["lane_cut", "lane_drift", "lane_hook", "lane_shift", "lane_weave", "side_dive", "side_traverse", "side_turn", "skirmish_figure8", "skirmish_loop", "straight_charge", "straight_crawl", "straight_medium", "straight_slow"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn": {"identity": "straight_slow", "eligible": ["lane_drift", "lane_shift", "lane_weave", "straight_charge", "straight_medium", "straight_slow"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"identity": "skirmish_figure8", "eligible": ["lane_hook", "loiter_high", "loiter_low", "loiter_mid", "skirmish_figure8", "skirmish_loop"]},
	"res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn": {"identity": "loiter_high", "eligible": ["loiter_high", "side_traverse"]},
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "straight_medium", "straight_fast", "straight_charge"]},
	"res://scenes/enemies/factions/corporate/enemy_sapper.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni"]},
	"res://scenes/enemies/factions/privateer/enemy_dart.tscn": {"identity": "straight_fast", "eligible": ["straight_fast", "straight_charge", "straight_reflex"]},
	"res://scenes/enemies/factions/privateer/enemy_gunship.tscn": {"identity": "hunt_omni", "eligible": ["loiter_mid", "hunt_omni", "loiter_low", "loiter_high", "straight_crawl"]},
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn": {"identity": "side_dive", "eligible": ["side_dive", "straight_medium", "straight_fast", "straight_charge", "side_turn", "lane_cut", "lane_shift"]},
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "lane_weave", "lane_drift", "lane_shift", "lane_cut", "drift_high"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"identity": "loiter_mid", "eligible": ["loiter_mid", "lane_drift", "lane_shift", "loiter_low", "loiter_high", "straight_crawl", "loiter_sweep"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"identity": "straight_crawl", "eligible": ["straight_charge", "straight_crawl", "straight_medium", "straight_slow"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn": {"identity": "straight_medium", "eligible": ["lane_cut", "lane_drift", "lane_shift", "lane_weave", "straight_crawl", "straight_medium", "straight_slow"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn": {"identity": "straight_medium", "eligible": ["straight_medium", "straight_slow", "straight_crawl", "lane_drift", "lane_shift", "proximity_chase"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn": {"identity": "straight_fast", "eligible": ["straight_fast", "lane_drift", "lane_weave", "straight_charge", "straight_medium", "straight_crawl", "side_turn", "side_dive"]},
	"res://scenes/enemies/factions/privateer/enemy_rocket.tscn": {"identity": "straight_crawl", "eligible": ["straight_crawl", "loiter_low", "loiter_mid", "loiter_high", "straight_charge", "loiter_sweep"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"identity": "loiter_high", "eligible": ["loiter_low", "loiter_high", "loiter_mid", "hunt_omni", "straight_crawl", "lane_weave", "loiter_sweep"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"identity": "straight_crawl", "eligible": ["drift_mid", "straight_charge", "lane_drift", "lane_shift", "side_traverse", "straight_crawl", "straight_slow"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"identity": "straight_fast", "eligible": ["side_dive", "straight_fast", "straight_medium", "straight_charge", "lane_drift", "lane_shift", "lane_cut", "side_turn"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "lane_weave", "side_dive", "lane_shift", "lane_drift", "straight_charge", "straight_fast", "lane_cut", "side_turn"]},
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"identity": "loiter_sweep", "eligible": ["loiter_sweep"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn": {"identity": "drift_high", "eligible": ["drift_high"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"identity": "drift_high", "eligible": ["drift_high"]},
	"res://scenes/enemies/factions/zealot/enemy_firecore_cruiser.tscn": {"identity": "straight_crawl", "eligible": ["drift_mid", "loiter_low", "loiter_high", "loiter_mid", "side_traverse", "straight_crawl"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"identity": "straight_crawl", "eligible": ["lane_drift", "lane_shift", "straight_crawl", "straight_slow"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_retro.tscn": {"identity": "straight_crawl", "eligible": ["lane_drift", "straight_crawl", "lane_shift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_run.tscn": {"identity": "straight_crawl", "eligible": ["straight_crawl", "straight_medium"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"identity": "straight_charge", "eligible": ["straight_fast", "straight_charge", "hunt_beeline", "straight_reflex"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "straight_crawl", "lane_cut"]},
}


# The enemy's signature movement key, or "" if the scene isn't in the matrix.
static func identity_for(scene: String) -> String:
	var rec: Variant = DATA.get(scene, null)
	if rec == null:
		return ""
	return str(rec.get("identity", ""))


# The movement keys this enemy may be assigned (includes identity), or [] if unmapped.
static func eligible_for(scene: String) -> Array:
	var rec: Variant = DATA.get(scene, null)
	if rec == null:
		return []
	var e: Variant = rec.get("eligible", [])
	return e if e is Array else []


# The movement KEY make_movement should build for this roster entry. A "vary": true entry gets
# a flat-random pick from the scene's eligible set (needs >1 to vary). Otherwise the MATRIX
# identity drives (so the eligibility tool controls assignment); unmapped scenes fall back to
# the entry's own "movement".
static func resolve(entry: Dictionary) -> String:
	var scene: String = str(entry.get("scene", ""))
	if bool(entry.get("vary", false)):
		var elig: Array = eligible_for(scene)
		if elig.size() > 1:
			return str(elig[randi() % elig.size()])
	var id: String = identity_for(scene)
	if id != "":
		return id
	return str(entry.get("movement", "straight"))
