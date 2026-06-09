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

const DATA := {
	"res://scenes/enemies/core/enemy_bomb_drone.tscn": {"identity": "straight_fast", "eligible": ["straight_fast"]},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"identity": "loiter_low", "eligible": ["loiter_low"]},
	"res://scenes/enemies/core/enemy_crystal.tscn": {"identity": "loiter_high", "eligible": ["loiter_high"]},
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn": {"identity": "drift_mid", "eligible": ["drift_mid"]},
	"res://scenes/enemies/factions/corporate/enemy_c_dart.tscn": {"identity": "straight_fast", "eligible": ["straight_fast"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"identity": "lane_weave", "eligible": ["lane_weave"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn": {"identity": "straight_medium", "eligible": ["straight_medium"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn": {"identity": "straight_fast", "eligible": ["straight_fast"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"identity": "skirmish_loop", "eligible": ["loiter_low", "skirmish_loop"]},
	"res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn": {"identity": "loiter_low", "eligible": ["loiter_low"]},
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline"]},
	"res://scenes/enemies/factions/corporate/enemy_sapper.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni"]},
	"res://scenes/enemies/factions/privateer/enemy_dart.tscn": {"identity": "straight_fast", "eligible": ["straight_fast"]},
	"res://scenes/enemies/factions/privateer/enemy_gunship.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "lane_shift", "lane_weave", "loiter_mid", "skirmish_loop"]},
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn": {"identity": "top_dive", "eligible": ["top_dive"]},
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn": {"identity": "side_traverse", "eligible": ["side_traverse"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"identity": "loiter_mid", "eligible": ["loiter_mid"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"identity": "loiter_high", "eligible": ["loiter_high"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn": {"identity": "straight_medium", "eligible": ["straight_medium"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn": {"identity": "straight_fast", "eligible": ["straight_fast"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn": {"identity": "straight_fast", "eligible": ["lane_drift", "lane_weave", "straight_fast"]},
	"res://scenes/enemies/factions/privateer/enemy_rocket.tscn": {"identity": "lane_drift", "eligible": ["lane_drift"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"identity": "lane_weave", "eligible": ["lane_weave", "loiter_mid", "side_traverse"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"identity": "straight_medium", "eligible": ["side_traverse", "straight_crawl", "straight_medium"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"identity": "straight_fast", "eligible": ["lane_weave", "straight_fast", "top_dive"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "lane_weave", "top_dive"]},
	"res://scenes/enemies/factions/zealot/enemy_firecore_cruiser.tscn": {"identity": "lane_drift", "eligible": ["lane_drift", "loiter_low", "side_traverse"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"identity": "lane_drift", "eligible": ["lane_drift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_retro.tscn": {"identity": "skirmish_loop", "eligible": ["lane_drift", "loiter_mid", "skirmish_loop"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_run.tscn": {"identity": "straight_fast", "eligible": ["lane_weave", "straight_fast"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"identity": "straight_fast", "eligible": ["straight_charge", "straight_fast"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "straight_crawl"]},
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
