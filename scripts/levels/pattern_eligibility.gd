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
# records the tool unions in (mines/asteroid/burner) are intentionally NOT carried here —
# resolve() falls back to the roster entry's own movement for scenes absent from the matrix.
# Re-exported 2026-07-15 (Roman's pattern-eligibility pass): baked four previously-empty records now
# carrying real identities/eligibles — enemy_c_s_archer (path_dive_diagonal), enemy_c_s_specter
# (lane_cut), enemy_p_l_harrier (loiter), enemy_z_s_bloom (straight).
const DATA := {
	"res://scenes/enemies/core/enemy_core_bomber.tscn": {"identity": "drift", "eligible": ["drift", "side_traverse"]},
	"res://scenes/enemies/core/enemy_core_bomber_thin.tscn": {"identity": "drift", "eligible": ["drift", "side_traverse"]},
	"res://scenes/enemies/core/enemy_core_m_minelayer.tscn": {"identity": "side_traverse", "eligible": ["drift", "lane_cut", "lane_drift", "lane_shift", "lane_weave", "side_traverse"]},
	"res://scenes/enemies/core/enemy_core_s_caltrop.tscn": {"identity": "straight", "eligible": ["lane_cut", "lane_drift", "lane_hook", "lane_shift", "lane_weave", "side_traverse", "side_turn", "straight"]},
	"res://scenes/enemies/core/enemy_core_s_cobra.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "lane_drift", "lane_shift", "straight", "straight_charge"]},
	"res://scenes/enemies/core/enemy_core_s_dart.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "straight", "straight_charge"]},
	"res://scenes/enemies/core/enemy_core_s_flechette.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "straight", "straight_charge"]},
	"res://scenes/enemies/core/enemy_core_s_jet.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "lane_weave", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/core/enemy_cruiser.tscn": {"identity": "loiter", "eligible": ["drift", "loiter"]},
	"res://scenes/enemies/enemy_asteroid.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_bomblet.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine_armored.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine_gravity.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine_shield.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine_smart.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/enemy_mine_tether.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn": {"identity": "drift", "eligible": ["drift", "lane_drift", "lane_hook", "lane_shift", "lane_weave", "straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_l_hive.tscn": {"identity": "loiter", "eligible": ["loiter", "loiter_sweep"]},
	"res://scenes/enemies/factions/corporate/enemy_c_m_widow.tscn": {"identity": "loiter", "eligible": ["loiter", "straight_charge"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_archer.tscn": {"identity": "path_dive_diagonal", "eligible": ["path_dive_diagonal", "straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "lane_drift", "lane_shift", "lane_weave", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn": {"identity": "lane_hook", "eligible": ["lane_hook", "loiter", "path_back_and_forth_wide", "path_loop_exit", "path_skirmish_figure8", "path_skirmish_loop", "skirmish_figure8", "skirmish_loop", "skirmish_pendulum", "straight"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_sapper.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "proximity_chase"]},
	"res://scenes/enemies/factions/corporate/enemy_c_s_specter.tscn": {"identity": "lane_cut", "eligible": ["lane_cut", "path_corner_hook", "side_turn", "straight"]},
	"res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "lane_cut", "lane_drift", "lane_hook", "lane_weave", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_p_l_harrier.tscn": {"identity": "loiter", "eligible": ["loiter", "path_corner_hook", "path_skirmish_loop", "straight"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn": {"identity": "loiter", "eligible": ["lane_drift", "lane_shift", "loiter", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_gunship.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "loiter", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn": {"identity": "straight_charge", "eligible": ["lane_cut", "lane_shift", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn": {"identity": "straight", "eligible": ["straight", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_rocket.tscn": {"identity": "straight", "eligible": ["hunt_omni", "lane_drift", "lane_hook", "lane_shift", "loiter", "loiter_sweep", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/privateer/enemy_p_m_wing.tscn": {"identity": "drift", "eligible": ["drift", "side_traverse", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_frigate.tscn": {"identity": "side_traverse", "eligible": ["drift", "loiter", "side_traverse", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_breaker.tscn": {"identity": "side_turn", "eligible": ["lane_cut", "lane_drift", "lane_shift", "loiter", "side_turn"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_butcher.tscn": {"identity": "straight", "eligible": ["loiter", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_chaser.tscn": {"identity": "path_dive_diagonal", "eligible": ["loiter", "path_dive_diagonal", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_devastator.tscn": {"identity": "straight", "eligible": ["loiter", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_harasser.tscn": {"identity": "straight", "eligible": ["straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_hunter.tscn": {"identity": "straight_charge", "eligible": ["lane_drift", "lane_shift", "lane_weave", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn": {"identity": "loiter", "eligible": ["hunt_omni", "lane_weave", "loiter", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_push.tscn": {"identity": "straight", "eligible": ["drift", "lane_drift", "lane_shift", "side_traverse", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_ravager.tscn": {"identity": "loiter", "eligible": ["loiter", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_ruiner.tscn": {"identity": "loiter", "eligible": ["loiter", "path_back_and_forth_wide", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_m_scorcher.tscn": {"identity": "loiter", "eligible": ["loiter", "straight"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_abductor.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "loiter", "path_skirmish_figure8", "path_skirmish_loop"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_bully.tscn": {"identity": "straight_charge", "eligible": ["straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn": {"identity": "straight", "eligible": ["lane_cut", "lane_drift", "lane_shift", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_piercer.tscn": {"identity": "lane_drift", "eligible": ["hunt_beeline", "lane_drift", "lane_shift", "lane_weave"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "lane_cut", "lane_drift", "lane_shift", "lane_weave", "side_turn", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_spearhead.tscn": {"identity": "hunt_beeline", "eligible": ["hunt_beeline", "proximity_chase"]},
	"res://scenes/enemies/factions/supremacy/enemy_s_s_striker.tscn": {"identity": "straight", "eligible": ["path_dive_diagonal", "path_skirmish_figure8", "path_skirmish_loop", "side_traverse", "side_turn", "straight"]},
	"res://scenes/enemies/factions/zealot/boss_z_battleship.tscn": {"identity": "loiter", "eligible": ["drift", "loiter", "side_traverse", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn": {"identity": "loiter_sweep", "eligible": ["loiter_sweep"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn": {"identity": "drift", "eligible": ["drift"]},
	"res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn": {"identity": "drift", "eligible": ["drift"]},
	# Burner self-drives a straight vertical descent in tandem beam-pairs (enemy_burner.gd); its
	# roster movement is null (bespoke), so this entry never assigns a key — it exists only so
	# allows()/the wildcard filter stop FAILING OPEN on the empty record (a lone Burner must never
	# fill a wildcard slot). "straight" reflects the real descent; the tandem beat assigns no key.
	"res://scenes/enemies/factions/zealot/enemy_burner.tscn": {"identity": "straight", "eligible": ["straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_l_crusader.tscn": {"identity": "straight", "eligible": ["lane_drift", "lane_shift", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn": {"identity": "straight", "eligible": ["drift", "loiter", "side_traverse", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn": {"identity": "straight", "eligible": ["lane_drift", "lane_shift", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_bloom.tscn": {"identity": "straight", "eligible": ["path_back_and_forth", "path_back_and_forth_wide", "side_traverse", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_censer.tscn": {"identity": "straight", "eligible": ["drift", "hunt_beeline", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_crook.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "lane_drift", "lane_shift", "path_dive_diagonal", "side_turn", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_cross.tscn": {"identity": "hunt_omni", "eligible": ["hunt_omni", "loiter", "loiter_sweep", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn": {"identity": "straight", "eligible": ["straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn": {"identity": "straight", "eligible": ["lane_drift", "lane_shift", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_pilgrim.tscn": {"identity": "straight", "eligible": ["hunt_beeline", "lane_drift", "lane_shift", "lane_weave", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_rebuker.tscn": {"identity": "straight", "eligible": ["loiter", "loiter_sweep", "path_back_and_forth_wide", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_shiv.tscn": {"identity": "straight_charge", "eligible": ["hunt_beeline", "straight", "straight_charge"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_spear.tscn": {"identity": "loiter", "eligible": ["drift", "hunt_omni", "loiter", "loiter_sweep", "straight"]},
	"res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn": {"identity": "side_traverse", "eligible": ["lane_cut", "side_traverse", "straight"]},
	"res://scenes/enemies/ground/b_b_glass.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_f_bunker.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_f_cross.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_f_tank.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_s_glass.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_p_small.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_s_shed.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_f_farm.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_t_scatter.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_t_rocket.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_t_ball.tscn": {"identity": "", "eligible": []},
	"res://scenes/enemies/ground/b_t_wave.tscn": {"identity": "", "eligible": []},
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


# True if `key` is an eligible movement for `scene`. FAIL-OPEN (permissive) whenever we can't
# judge: scene=="" or key=="" (nothing to check), the scene is unmapped (eligible_for empty), or
# the key is an authored path_* flight (resolved via AuthoredPathLibrary, not the shape matrix —
# the eligibility matrix tracks SHAPE keys, so path_* keys are a class it doesn't govern and are
# never coerced). FAIL-CLOSED only when the scene IS mapped and the (shape) key is absent from its
# eligible list. `key` MUST already be alias-collapsed by the caller (see enemy_roster.
# MOVEMENT_ALIASES) — this file does NOT preload the roster (circular: the roster preloads this).
static func allows(scene: String, key: String) -> bool:
	if scene == "" or key == "":
		return true
	if key.begins_with("path_"):
		return true
	var elig: Array = eligible_for(scene)
	if elig.is_empty():
		return true
	return elig.has(key)


# Return `key` if the scene allows it; otherwise push_error (naming both scene and key) and coerce
# to a movement the scene actually supports: its identity pattern, else the first eligible key, else
# "straight". `key` MUST already be alias-collapsed by the caller.
static func guard_key(scene: String, key: String) -> String:
	if allows(scene, key):
		return key
	var fallback: String = identity_for(scene)
	if fallback == "":
		var elig: Array = eligible_for(scene)
		fallback = str(elig[0]) if not elig.is_empty() else "straight"
	push_error("PatternEligibility.guard_key: movement '%s' is not eligible for '%s' — coercing to '%s'." % [key, scene, fallback])
	return fallback


# The movement KEY make_movement should build for this roster entry. A "vary": true entry gets
# a flat-random pick from the scene's eligible set (needs >1 to vary). Otherwise the MATRIX
# identity drives (so the eligibility tool controls assignment); unmapped scenes fall back to
# the entry's own "movement".
#
# OMNI-RESPECT (2026-07-18): the one exception to identity-drives. An omni-capable scene carries a
# "hunt_omni" matrix identity, and identity-drives means that identity used to STOMP whatever movement
# a roster entry ASSIGNED — so an omni hull could never be fielded with a non-omni movement; it always
# dropped into omni-hunt (designer: "omni capable enemies should respect the movement pattern they've
# been assigned"). Now: when the identity is hunt_omni but the entry explicitly assigns a DIFFERENT,
# eligible, NON-omni movement, that assigned key wins. Entries that assign hunt_omni (the gunship/
# abductor/sapper anchors) keep hunting, and every NON-omni identity still drives unchanged (the
# eligibility tool stays the SSOT for all other enemies), so this is scoped strictly to the omni case.
static func resolve(entry: Dictionary) -> String:
	var scene: String = str(entry.get("scene", ""))
	if bool(entry.get("vary", false)):
		var elig: Array = eligible_for(scene)
		if elig.size() > 1:
			return str(elig[randi() % elig.size()])
	var id: String = identity_for(scene)
	if id == "hunt_omni":
		var assigned: String = str(entry.get("movement", ""))
		if assigned != "" and assigned != "hunt_omni" and allows(scene, assigned):
			return assigned
	if id != "":
		return id
	return str(entry.get("movement", "straight"))
