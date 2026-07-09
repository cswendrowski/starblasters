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
# Keys are the make_movement SHAPE keys only (locomotion refactor 2026-06-20): the speed/depth
# variants (straight_fast, loiter_high, drift_mid, side_traverse_low…) collapsed to their shape
# (straight/loiter/drift/side_traverse) once speed became chassis-owned and depth a per-enemy axis.
# Each enemy's hold/cross depth now rides an explicit "depth" on its roster ENTRY, not the key.

# Exported from the Pattern Eligibility dev tool (user://tuners/pattern_eligibility.json),
# 2026-06-09; collapsed to shape-only keys 2026-06-20. Strafer dropped (retired); "beam_sweep"
# renamed to "loiter_sweep". Re-exported 2026-06-21 (Roman's authoring pass): identity/eligible
# edits across ~20 enemies + two new entries (enemy_core_s_jet, enemy_p_m_wing). Empty-identity
# records the tool unions in (mines/asteroid/burner/bloom) are intentionally NOT carried here —
# resolve() falls back to the roster entry's own movement for scenes absent from the matrix.
const DATA := {
	"res://scenes/enemies/core/enemy_core_bomber.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/core/enemy_core_bomber_thin.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"identity": "loiter", "eligible": ["drift", "loiter"]},
	"res://scenes/enemies/factions/corporate/enemy_c_m_widow.tscn": {"identity": "loiter", "eligible": ["loiter", "straight_charge"]},
	"res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "lane_drift", "lane_shift", "lane_weave", "side_turn", "straight_charge", "straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"identity": "lane_hook", "eligible": ["lane_hook", "loiter", "skirmish_figure8", "skirmish_loop"]},
	"res://scenes/enemies/factions/corporate/enemy_c_l_hive.tscn": {"identity": "loiter", "eligible": ["loiter", "loiter_sweep"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_sapper.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni"]},
	"res://scenes/enemies/core/enemy_core_s_dart.tscn": {"identity": "straight", "eligible": ["straight", "straight_charge", "hunt_beeline"]},
	"res://scenes/enemies/core/enemy_core_s_flechette.tscn": {"identity": "straight", "eligible": ["straight", "straight_charge", "hunt_beeline"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn": {"identity": "hunt_omni", "eligible": ["loiter", "hunt_omni", "straight", "loiter_sweep"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn": {"identity": "side_turn", "eligible": ["side_turn", "straight", "straight_charge", "lane_cut", "lane_shift"]},
	"res://scenes/enemies/core/enemy_core_m_minelayer.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "lane_weave", "lane_drift", "lane_shift", "lane_cut", "drift"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"identity": "loiter", "eligible": ["loiter", "lane_drift", "lane_shift", "straight", "loiter_sweep"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"identity": "straight", "eligible": ["straight_charge", "straight"]},
	"res://scenes/enemies/core/enemy_core_s_caltrop.tscn": {"identity": "straight", "eligible": ["lane_cut", "lane_drift", "lane_shift", "lane_weave", "straight", "lane_hook"]},
	"res://scenes/enemies/core/enemy_core_s_cobra.tscn": {"identity": "straight", "eligible": ["straight", "lane_drift", "lane_shift", "hunt_beeline", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn": {"identity": "straight", "eligible": ["straight", "lane_drift", "lane_weave", "straight_charge", "side_turn", "hunt_beeline", "lane_cut", "lane_hook"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_rocket.tscn": {"identity": "straight", "eligible": ["straight", "loiter", "straight_charge", "loiter_sweep", "lane_drift", "lane_shift", "lane_hook", "hunt_omni"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"identity": "loiter", "eligible": ["loiter", "hunt_omni", "straight", "lane_weave", "loiter_sweep"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"identity": "straight", "eligible": ["drift", "straight_charge", "lane_drift", "lane_shift", "side_traverse", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"identity": "straight", "eligible": ["side_turn", "straight", "straight_charge", "lane_drift", "lane_shift", "lane_cut"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "lane_weave", "side_turn", "lane_shift", "lane_drift", "straight_charge", "straight", "lane_cut"]},
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"identity": "loiter_sweep", "eligible": ["loiter_sweep"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn": {"identity": "straight", "eligible": ["drift", "loiter", "side_traverse", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_l_crusader.tscn": {"identity": "straight", "eligible": ["straight", "lane_drift", "lane_shift", "loiter_sweep"]},
	# Zealot Battleship (mega-boss). Movement is driven by the boss encounter state machine, so this
	# entry is cosmetic — it just keeps the Enemy Bench / eligibility tools from falling back to a
	# placeholder key when the boss is selected. "loiter" reads as the capital holding high in the band.
	"res://scenes/enemies/factions/zealot/boss_z_battleship.tscn": {"identity": "loiter", "eligible": ["loiter", "drift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"identity": "straight", "eligible": ["lane_drift", "lane_shift", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn": {"identity": "straight", "eligible": ["lane_drift", "straight", "lane_shift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn": {"identity": "straight", "eligible": ["straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"identity": "straight_charge", "eligible": ["straight", "straight_charge", "hunt_beeline"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "straight", "lane_cut"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_censer.tscn": {"identity": "straight", "eligible": ["drift", "straight", "straight_charge", "hunt_beeline"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_crook.tscn": {"identity": "straight", "eligible": ["straight", "lane_drift", "hunt_beeline", "lane_shift"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_cross.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "straight", "loiter", "straight_charge", "loiter_sweep"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_pilgrim.tscn": {"identity": "straight", "eligible": ["straight", "lane_weave", "lane_drift", "lane_shift", "hunt_beeline"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_rebuker.tscn": {"identity": "straight", "eligible": ["loiter", "straight", "loiter_sweep"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_spear.tscn": {"identity": "loiter", "eligible": ["drift", "hunt_omni", "loiter", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn": {"identity": "side_traverse", "eligible": ["side_traverse", "loiter", "drift", "straight", "straight_charge"]},
	"res://scenes/enemies/core/enemy_core_s_jet.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "lane_weave", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_wing.tscn": {"identity": "drift", "eligible": ["drift", "side_turn", "side_traverse", "straight", "straight_charge"]},
}


# Canonical SHAPE-only movement keys (locomotion refactor 2026-06-19): speed + depth are chassis/
# formation axes now, not movement keys. Speed = size base + per-enemy engine (Enemy Bench Locomotion
# tab); depth = enemy default + per-placement override. This is the SINGLE canonical list — it moved
# here from pattern_eligibility_editor.gd:27 (2026-07-07 dev-tool unification) so DevData.movement_keys()
# composes `canonical shapes + live authored paths` and BOTH the eligibility editor and Formation Builder
# read it via DevData instead of hand-maintaining a private copy. The trailing HAZARD drift modes are
# selectable in the wave editor for asteroid/mine/firecore placements (LateralDrift envelopes); on a
# combat enemy they fall back to a straight descent, so they're harmless there.
const MOVEMENT_KEYS := [
	"straight", "straight_charge",
	"skirmish_loop", "skirmish_figure8", "skirmish_pendulum",
	"drift",
	"loiter",
	"lane_weave", "lane_drift", "lane_shift", "lane_hook", "lane_cut",
	"side_turn", "side_traverse",
	"hunt_beeline", "hunt_omni",
	"proximity_chase", "loiter_sweep",
	"drift_lane", "drift_adjacent", "drift_all",
]


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
