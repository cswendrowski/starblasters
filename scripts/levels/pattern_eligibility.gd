extends Object

# Pattern eligibility (docs/pattern_eligibility_2026-06-08.md). Per enemy SCENE:
#   identity — its signature movement key (used unless an entry opts into variety).
#   eligible — the movement keys it MAY be assigned (always includes identity).
#
# The conductor resolves an entry's movement key through resolve(): a "vary": true entry gets a
# flat-random eligible key; everything else keeps its own movement (its identity). So this is
# BEHAVIOR-PRESERVING — nothing moves differently until eligibility is expanded AND an entry
# opts in. Bespoke-movement enemies (bomber, beam-shooters, firecore_drone — entry movement
# null) are deliberately absent; they move via their own scripts, not make_movement.
#
# COMMITTED source of truth (ships in the pck). The lane-visualizer pattern tab will edit
# user://tuners/pattern_eligibility.json and EXPORT back to this DATA const — production never
# reads user://. Preload-referenced, NOT a global class_name (headless-safe), mirroring
# factions.gd. SEEDED from the roster by tools/gen_pattern_eligibility.gd (2026-06-08).

const DATA := {
	"res://scenes/enemies/core/enemy_bomb_drone.tscn": {"identity": "fast_straight", "eligible": ["fast_straight"]},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"identity": "loiter", "eligible": ["loiter"]},
	"res://scenes/enemies/core/enemy_crystal.tscn": {"identity": "loiter_high", "eligible": ["loiter_high"]},
	"res://scenes/enemies/factions/corporate/enemy_bulwark.tscn": {"identity": "bulwark_drift", "eligible": ["bulwark_drift"]},
	"res://scenes/enemies/factions/corporate/enemy_c_dart.tscn": {"identity": "fast_straight", "eligible": ["fast_straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"identity": "lane_weave", "eligible": ["lane_weave"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn": {"identity": "firecore_straight", "eligible": ["firecore_straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn": {"identity": "fast_straight", "eligible": ["fast_straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"identity": "advance_retreat", "eligible": ["advance_retreat", "loiter"]},
	"res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn": {"identity": "loiter", "eligible": ["loiter"]},
	"res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn": {"identity": "beeline", "eligible": ["beeline"]},
	"res://scenes/enemies/factions/corporate/enemy_sapper.tscn": {"identity": "omni", "eligible": ["omni"]},
	"res://scenes/enemies/factions/privateer/enemy_dart.tscn": {"identity": "fast_straight", "eligible": ["fast_straight"]},
	"res://scenes/enemies/factions/privateer/enemy_gunship.tscn": {"identity": "omni", "eligible": ["advance_retreat", "lane_shift", "lane_weave", "loiter_mid", "omni"]},
	"res://scenes/enemies/factions/privateer/enemy_interceptor.tscn": {"identity": "top_dive", "eligible": ["top_dive"]},
	"res://scenes/enemies/factions/privateer/enemy_minelayer.tscn": {"identity": "side_traverse", "eligible": ["side_traverse"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"identity": "loiter_mid", "eligible": ["loiter_mid"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"identity": "loiter_high", "eligible": ["loiter_high"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_drop.tscn": {"identity": "firecore_straight", "eligible": ["firecore_straight"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_gray.tscn": {"identity": "fast_straight", "eligible": ["fast_straight"]},
	"res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn": {"identity": "fast_straight", "eligible": ["fast_straight", "lane_drift", "lane_weave"]},
	"res://scenes/enemies/factions/privateer/enemy_rocket.tscn": {"identity": "lane_drift", "eligible": ["lane_drift"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"identity": "lane_weave", "eligible": ["lane_weave", "loiter_mid", "side_traverse"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"identity": "firecore_straight", "eligible": ["firecore_straight", "side_traverse", "slow_advance"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"identity": "fast_straight", "eligible": ["fast_straight", "lane_weave", "top_dive"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"identity": "beeline", "eligible": ["beeline", "lane_weave", "top_dive"]},
	"res://scenes/enemies/factions/zealot/enemy_firecore_cruiser.tscn": {"identity": "lane_drift", "eligible": ["lane_drift", "loiter", "side_traverse"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"identity": "lane_drift", "eligible": ["lane_drift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_retro.tscn": {"identity": "advance_retreat", "eligible": ["advance_retreat", "lane_drift", "loiter_mid"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_run.tscn": {"identity": "fast_straight", "eligible": ["fast_straight", "lane_weave"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"identity": "fast_straight", "eligible": ["fast_straight", "lane_charge"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "slow_advance"]},
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


# The movement KEY make_movement should build for this roster entry. Identity (the entry's own
# "movement") unless the entry opts into variety with "vary": true, in which case a flat-random
# pick from the scene's eligible set (needs >1 to vary). Unmapped scenes / vary-off keep the
# entry's movement, so this is a no-op until eligibility is expanded + an entry opts in.
static func resolve(entry: Dictionary) -> String:
	var fallback: String = str(entry.get("movement", "straight"))
	if not bool(entry.get("vary", false)):
		return fallback
	var elig: Array = eligible_for(str(entry.get("scene", "")))
	if elig.size() <= 1:
		return fallback
	return str(elig[randi() % elig.size()])
