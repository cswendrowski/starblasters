extends "res://scripts/enemies/bosses/physics_boss.gd"

# THE DIRECTOR — a CORPORATE multi-part MEGA-BOSS. Shares the battleship's thrust locomotion (physics_boss).
# The FIGHT IS THE SECTIONS (Roman 2026-07-08, battleship model): the hull is pass-through
# (monitorable=false) and the destructible SECTIONS are the only targets — 7 body sections (each wraps an
# authored Collision* polygon, reparented into its own Area2D) + 2 wing cannons. Destroy ALL → death (or it
# retreats if it outlives its maneuver cycle). Each section, on death, reveals a Destroyed* damage overlay,
# disables its weapon, and plays an instakill+blowout FX: FENDERS L/R disable that side's cannon + muzzle;
# HOOD/MISSILE is a 2-STAGE section (hood first, re-arm, then missiles — disabling missiles); WING CANNONS
# disable their beam. A section hit also JOLTS the whole boss (asteroid-style knock-away). Hull faces UP.
#
# It is director-gated exactly like the battleship: present from wave 1, idles off-screen, and plays ONE
# between-wave MANEUVER (the director awaits it) plus periodic during-wave INTERLUDES (a hazard loop):
#   Between-wave (play_wave_maneuver):
#     gun_charge   — arrive centre lane, hold, fire cannons+muzzles ×3, then rush down the middle.
#     laser_lane   — arrive centre lane, fire the wing beams down the lane (if ≥1 alive), fly down it.
#     missile_weave— arrive centre lane, open the bay, fire a homing missile salvo, close, weave off L/R.
#   During-wave interludes (on_wave_started arms the loop from wave 2):
#     missile_barrage    — missile-cruiser style: park in bg, lob salvos of 6 up into the play area
#                          (FRIENDLY FIRE — hits player AND enemies), fly off.
#     missile_lane_strike— (boss stays OFF-SCREEN) mark 6 non-overlapping spots down a lane; missiles streak
#                          in from the nearest edge + explode (FF). +1 lane each pass, capped 5, ≥1 free.
#
# Scene overhaul (Roman 2026-07-07): single-frame Body sprite; the wing cannons are now AUTHORED sub-scene
# instances (boss_c_director_wingcannon.tscn → boss_c_director_wing.gd) placed under Body; the flechette
# lifts / bay doors / flechette wave are CUT; the missile bay is just the animated MissileCover.

const WingScript = preload("res://scripts/enemies/bosses/boss_c_director_wing.gd")
const SectionScript = preload("res://scripts/enemies/bosses/boss_c_director_section.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const DriftingMissile = preload("res://scenes/projectiles/drifting_missile.tscn")

# The DESTRUCTIBLE SECTIONS (Roman 2026-07-08). Each wraps an authored Collision* polygon; destroying it
# reveals the matching body Destroyed* overlay + disables its weapon(s). "weapons" is per-stage. The shared
# HOOD+MISSILE section is 2-STAGE (destroy → hood, re-arm → destroy → missiles), so hood always goes first.
# The 2 wing cannons are separate parts (WingCannonL/R). Kill ALL sections + wings → death.
const SECTION_DEFS := [
	{"poly": "CollisionWingL",        "id": "wing_l",       "overlays": ["DestroyedWing"],                 "weapons": [[]]},
	{"poly": "CollisionWingR",        "id": "wing_r",       "overlays": ["DestroyedWing2"],                "weapons": [[]]},
	{"poly": "CollisionEngineL",      "id": "engine_l",     "overlays": ["DestroyedEngineL"],              "weapons": [[]]},
	{"poly": "CollisionEngineR",      "id": "engine_r",     "overlays": ["DestroyedEngineR"],              "weapons": [[]]},
	{"poly": "CollisionFenderL",      "id": "fender_l",     "overlays": ["DestroyedFenderL"],              "weapons": [["cannon_l", "muzzle_l"]]},
	{"poly": "CollisionFenderR",      "id": "fender_r",     "overlays": ["DestroyedFenderR"],              "weapons": [["cannon_r", "muzzle_r"]]},
	{"poly": "CollisionHood+Missile", "id": "hood_missile", "overlays": ["DestroyedHood", "DestroyedMissile"], "weapons": [[], ["missiles"]]},
]
# CORPO GUNS: family-tagged variants swapped to the corporate skin (frame 2 = lime) at fire time via
# BulletCatalog — the same path a wave gunner uses (bosses aren't stamped with faction_skin, so we resolve
# it ourselves). Cannons fire the `bolt` family, muzzles the `laser` family (matches the Archer/roster).
const BulletCatalog = preload("res://scripts/projectiles/bullet_catalog.gd")
const BV_Bolt = preload("res://data/bullets/bolt.tres")
const BV_Laser = preload("res://data/bullets/laser.tres")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
const EnemySfx = preload("res://scripts/effects/enemy_sfx.gd")
const WeaponSfx = preload("res://scripts/effects/weapon_sfx.gd")
const CORP_SKIN := 2   # Factions.Id.CORPORATE — the frame-2 (lime) bullet reskin

# THRUSTER LAYOUT (local coords, nose = -Y; plume_rotation = where the flare plume POINTS). Groups match
# physics_boss._update_flares: main (rear), spos/sneg (side strafe jets), ycw/yccw (diagonal yaw RCS),
# top (inner divers, into the background). Sized to the new ~123 × 138 hull (Engine markers ±24,68); Lab-tunable.
const THRUSTER_DEFS := [
	["main", Vector2(-24, 68), 0.0], ["main", Vector2(24, 68), 0.0],
	["spos", Vector2(-42, -18), 0.5 * PI], ["spos", Vector2(-42, 45), 0.5 * PI],
	["sneg", Vector2(42, -18), -0.5 * PI], ["sneg", Vector2(42, 45), -0.5 * PI],
	["ycw", Vector2(-34, -52), 0.5 * PI], ["ycw", Vector2(34, 62), -0.5 * PI],
	["yccw", Vector2(34, -52), -0.5 * PI], ["yccw", Vector2(-34, 62), 0.5 * PI],
	["top", Vector2(-12, -6), PI], ["top", Vector2(12, -6), PI],
	["top", Vector2(-12, 38), PI], ["top", Vector2(12, 38), PI],
]

# --- tunables (@export → Director Lab) ---
@export var SECTION_HP: int = 55             # HP per section (per STAGE for the 2-stage hood/missile)
@export var SECTION_DEBRIS: int = 7          # debris pieces flung off a section when it's destroyed
@export var WING_HP: int = 100
@export var ARRIVE_Y: float = 80.0           # facing-down hold-Y for the on-screen combat maneuvers (centre)
@export var PARK_Y: float = 52.0             # bg-park hold-Y for the interludes
@export var GUN_VOLLEYS: int = 3             # gun_charge fires this many times
@export var GUN_BEAT: float = 0.55           # seconds between gun volleys
@export var WING_BEAM_HOLD: float = 2.6      # hold in the lane while the wing beams fire
@export var RUSH_DUR: float = 4.0            # exit-fly TIMEOUT cap (it returns as soon as it's fully off-screen)
@export var KNOCK_UP: float = 62.0           # shot knock-away: upward impulse (away from the below-screen shooter)
@export var KNOCK_SIDE: float = 34.0         # shot knock-away: random lateral spread
@export var KNOCK_GRACE: float = 0.07        # min seconds between knock impulses (so a bullet stream doesn't compound)
@export var MISSILE_SALVO: int = 6           # missiles per weave / barrage salvo
@export var MISSILE_SHOT_DELAY: float = 0.25 # in-lane missiles cycle the muzzles this far apart (not all at once)
@export var BARRAGE_SALVO_GAP: float = 2.0   # gap between a barrage salvo's end and the next salvo's telegraph
@export var LANE_STRIKE_SPOTS: int = 6       # marks per lane in the lane-strike hazard
@export var STRIKE_TELEGRAPH: float = 1.1    # warning time before the lane-strike missiles streak in
@export var SKIRMISH_STOPS: int = 6          # cannon-skirmish firing stops (centre / side / centre / …)
@export var SKIRMISH_SLIDE_X: float = 60.0   # how far the skirmish slides off-centre
@export var SKIRMISH_BURST_SHOTS: int = 3    # gun volleys per skirmish burst
@export var SKIRMISH_BURST_GAP: float = 0.18 # gap between volleys within a skirmish burst
@export var SKIRMISH_MISSILES: int = 3       # missiles in the skirmish's every-other missile burst
@export var HAZARD_MIN_GAP: float = 8.0      # interlude cadence MIN (once armed)
@export var HAZARD_MAX_GAP: float = 13.0

# --- runtime ---
var _wings: Array = []             # the two boss_c_director_wing parts
var _busy: bool = false            # a maneuver OR interlude owns the boss (serializes the two)
var _hazards_active: bool = false  # interludes armed (from wave 2)
var _hazard_loop_started: bool = false
var _last_maneuver: String = ""
var _side_flip: int = 0
var _lane_strike_passes: int = 0   # +1 lane per lane-strike pass (capped)
var _barrage_passes: int = 0       # +1 salvo per missile-barrage pass (capped)
var _knock_grace_t: float = 0.0    # cooldown on the shot knock-away
var _guns_firing: bool = false     # cannons + muzzles spray while true + on-screen (no dead air)
var _gun_cd: float = 0.0           # gun-volley cadence accumulator
var _wing_overlays: Dictionary = {}   # wing part → its body DestroyedCannonL/R overlay (shown on wing death)
var _sections: Array = []          # boss_c_director_section parts (the 7 body sections)
var _section_meta: Dictionary = {} # section id → its SECTION_DEFS entry (overlays + per-stage weapons)
# Weapon-alive flags — a destroyed section disables its weapon(s).
var _cannon_l: bool = true
var _cannon_r: bool = true
var _muzzle_l: bool = true
var _muzzle_r: bool = true
var _missiles_ok: bool = true

# cached scene nodes
var _missile_cover: Sprite2D = null


func _ready() -> void:
	max_health = 1000            # placeholder (boss convention: set before super._ready()); recomputed from parts below
	bounty_value = 800
	display_scale = 1.0
	_initial_state = &"IDLE"    # one benign IDLE state → skips the legacy HP-ladder; maneuvers are external
	super._ready()
	_scripted_move = true       # physics_boss owns position; boss_base._process won't clamp/anchor it
	# The FIGHT IS THE SECTIONS (Roman 2026-07-08, battleship model): the hull itself is NOT a bullet target
	# (monitorable=false); the destructible SECTIONS + wing cannons are. Killing every one → death.
	monitorable = false
	z_index = UNDER_LAYER_Z
	_pin_body_under_layer()
	_missile_cover = get_node_or_null("Body/MissileCover") as Sprite2D
	_reset_bay_visuals()
	_build_wing_cannons()
	_build_sections()
	_build_thruster_flares()
	# HP bar = the aggregate of every destructible part (sections + wing cannons), like the battleship. A
	# 2-stage section counts BOTH stages (bar_max) so the bar reflects the true damage to clear it.
	var total: int = 0
	for p in live_parts():
		if p.has_method("bar_max"):
			total += int(p.bar_max())
		elif "max_hp" in p:
			total += int(p.max_hp)
	if total > 0:
		max_health = total
		health = total
		health_changed.emit(health, max_health)


# ---- physics_boss / boss_base hooks -------------------------------------

func _thruster_defs() -> Array:
	return THRUSTER_DEFS


# The Director's hull is a single "Body" sprite (Roman 2026-07-07 overhaul).
func _pinned_body_names() -> Array:
	return ["Body"]


func _stop_firing() -> void:
	_set_wings(false)


func _build_states() -> void:
	add_state(&"IDLE")


func _state_enter(_state_name: StringName) -> void:
	pass


# No hull-mounted auto-gun (the maneuvers fire the cannons/muzzles/beams) + no engine trail.
func _on_shoot_timer_timeout() -> void:
	pass


func _attach_engine_trail() -> void:
	pass


# ---- Knock-away (asteroid-style, on a section being shot) ---------------

# A section was shot → shove the whole boss (physics_boss.knockback adds to _vel; drag + the pilot recover
# it). Up/away from the below-screen shooter, with lateral spread. Graced so a bullet stream doesn't
# compound. Called by boss_c_director_section.take_hit (the hull itself is monitorable=false).
func section_was_hit() -> void:
	if _dying or _knock_grace_t > 0.0:
		return
	_knock_grace_t = KNOCK_GRACE
	knockback(Vector2(randf_range(-KNOCK_SIDE, KNOCK_SIDE), -KNOCK_UP))


func _process(delta: float) -> void:
	super._process(delta)   # physics_boss: boss_base._process + _integrate_physics
	if get_tree().paused:
		return
	if _knock_grace_t > 0.0:
		_knock_grace_t -= delta
	_update_health_bar()
	# Continuous gun cadence: while a maneuver has the guns hot AND the body is on-screen, spray a volley
	# every GUN_BEAT — so the boss is actually shooting instead of sitting in dead air (Roman 2026-07-06).
	if _guns_firing and not _dying and _body_on_screen():
		_gun_cd -= delta
		if _gun_cd <= 0.0:
			_gun_cd = maxf(0.12, GUN_BEAT)
			_fire_gun_volley()
	else:
		_gun_cd = 0.0   # fire immediately when it next comes on-screen / re-arms


# ---- Part construction --------------------------------------------------

# Wing cannons are AUTHORED sub-scene instances (WingCannonL/R under Body) shipped SCRIPT-LESS by Roman as
# template shells (Body sprite + capsule hitbox + Muzzle marker). Attach the wing part script at runtime
# and init it, register as a destructible part, and map it to its body-mounted DestroyedL/R overlay (shown
# on death via _on_part_lost). No procedural sprite/hitbox — the sub-scene provides those.
func _build_wing_cannons() -> void:
	_wings = []
	_wing_overlays = {}
	for pair in [["WingCannonL", "DestroyedCannonL"], ["WingCannonR", "DestroyedCannonR"]]:
		var w = find_child(String(pair[0]), true, false)
		if w == null:
			continue
		if w.get_script() != WingScript:
			w.set_script(WingScript)   # the instances ship script-less on purpose — the boss sets them up
		w.boss_ref = self
		if w.has_method("init_wing"):
			w.init_wing(WING_HP)
		var overlay := find_child(String(pair[1]), true, false) as CanvasItem
		if overlay != null:
			overlay.visible = false
			_wing_overlays[w] = overlay
		_wings.append(w)
		register_part(w)


# A part was destroyed. Wing cannons reveal their body overlay + play the section FX here (their live
# cannon hid itself); the 7 body sections already handled their overlay/weapon/FX via section_stage. When
# EVERY part is gone the fight is won → death.
func _on_part_lost(part: Node) -> void:
	if _wing_overlays.has(part):
		var ov = _wing_overlays[part] as CanvasItem
		if is_instance_valid(ov):
			ov.visible = true
		if part is Node2D:
			_section_fx((part as Node2D).global_position)
	if not _dying and live_parts().is_empty():
		_death_sequence()


# Wrap each authored Collision* polygon in its own section part (reparented in) so bullets hit the specific
# section. Map each to its Destroyed* overlay(s) + per-stage weapon disables (see SECTION_DEFS).
func _build_sections() -> void:
	_sections = []
	_section_meta = {}
	for def in SECTION_DEFS:
		var poly := get_node_or_null(String(def["poly"])) as CollisionPolygon2D
		if poly == null:
			continue
		var num_stages: int = (def["overlays"] as Array).size()
		var sec = SectionScript.new()
		add_child(sec)
		poly.reparent(sec)                 # move the whole-ship polygon into the section's own Area2D
		sec.setup_section(self, String(def["id"]), SECTION_HP, num_stages)
		sec.section_stage.connect(_on_section_stage)
		_sections.append(sec)
		_section_meta[String(def["id"])] = def
		register_part(sec)


# A section stage completed → reveal that stage's overlay, disable its weapon(s), and blow debris off it.
func _on_section_stage(sec: Node, stage: int) -> void:
	var def = _section_meta.get(sec.section_id, null) if sec != null else null
	if def == null:
		return
	var overlays: Array = def["overlays"]
	if stage < overlays.size():
		var ov := _find_overlay(String(overlays[stage]))
		if ov != null:
			ov.visible = true
	var weapons: Array = def["weapons"]
	if stage < weapons.size():
		for wkey in weapons[stage]:
			_disable_weapon(String(wkey))
	_section_fx(_section_center(sec))


func _find_overlay(nm: String) -> CanvasItem:
	var ov := get_node_or_null("Body/" + nm) as CanvasItem
	if ov == null:
		ov = find_child(nm, true, false) as CanvasItem
	return ov


func _disable_weapon(key: String) -> void:
	match key:
		"cannon_l": _cannon_l = false
		"cannon_r": _cannon_r = false
		"muzzle_l": _muzzle_l = false
		"muzzle_r": _muzzle_r = false
		"missiles": _missiles_ok = false


# The world-space centre of a section = the centroid of its reparented collision polygon (falls back to
# the part origin). The debris + blast play THERE, localized to the destroyed part.
func _section_center(part: Node) -> Vector2:
	if part == null or not (part is Node2D):
		return global_position
	for c in part.get_children():
		if c is CollisionPolygon2D:
			var poly: PackedVector2Array = (c as CollisionPolygon2D).polygon
			if poly.size() > 0:
				var sum := Vector2.ZERO
				for pt in poly:
					sum += pt
				return (c as CollisionPolygon2D).to_global(sum / float(poly.size()))
	return (part as Node2D).global_position


# On-boss, LOCALIZED section-destroy FX: a blast at the section + a spray of debris pieces flung OFF the
# area (radiating away from the hull centre, biased downward as they fall). Roman 2026-07-08 (replaces the
# earlier decal-standin DeathEffects styles).
func _section_fx(center: Vector2) -> void:
	var world: Node = _world()
	if world == null:
		return
	ExplosionFx.play(center, 1.1, true, world, ExplosionFx.scene_for("default"))
	ExplosionFx.play(center, 0.7, false, world, ExplosionFx.scene_for("small_circle"))
	var away: Vector2 = center - global_position
	away = away.normalized() if away.length() > 1.0 else Vector2.UP
	for _i in SECTION_DEBRIS:
		var dir: Vector2 = Vector2.RIGHT.rotated(away.angle() + randf_range(-1.2, 1.2))
		dir.y += 0.5   # debris tends downward as it's flung off
		ShipDebrisEmber.spawn(world, center, {
			"velocity": dir.normalized() * randf_range(70.0, 160.0),
			"spin": randf_range(-7.0, 7.0),
			"piece_scale": randf_range(0.7, 1.3),
		})


# All sections + wing cannons destroyed → the fight is won. Dramatic multi-blast death (bounty + free).
func _death_sequence() -> void:
	if _dying:
		return
	_hazards_active = false
	_guns_firing = false
	_set_wings(false)
	_depth = 0.0
	_depth_vel = 0.0
	_apply_depth()
	explode()   # boss_base: multi-blast cascade + died.emit(bounty) + Run.on_boss_defeated + free


# Drive the HP bar off the live aggregate part HP (sections + wing cannons), like the battleship.
func _update_health_bar() -> void:
	if _dying or max_health <= 0:
		return
	var cur: int = 0
	for p in live_parts():
		if not is_instance_valid(p) or not ("hp" in p):
			continue
		if "_destroyed" in p and p._destroyed:
			continue
		cur += int(p.bar_hp()) if p.has_method("bar_hp") else maxi(0, int(p.hp))
	if cur != health:
		health = cur
		health_changed.emit(health, max_health)


func _wings_alive() -> bool:
	for w in _wings:
		if is_instance_valid(w) and not w.is_destroyed():
			return true
	return false


func _set_wings(on: bool) -> void:
	for w in _wings:
		if is_instance_valid(w):
			w.set_active(on)


# ---- Director API (called by director.gd boss_gate) ---------------------

func play_wave_maneuver(_wave_idx: int = 0) -> void:
	await _run_maneuver(_pick_maneuver())


# Dev (Director Lab): play a SPECIFIC maneuver/interlude on demand.
func play_named_maneuver(name: String) -> void:
	await _run_maneuver(name)


const MANEUVER_NAMES := ["gun_charge", "laser_lane", "missile_weave", "cannon_skirmish",
	"missile_barrage", "missile_lane_strike"]


func _run_maneuver(m: String) -> void:
	if _dying or not is_instance_valid(self):
		return
	while _busy and not _dying:
		await get_tree().process_frame
	if _dying:
		return
	_busy = true
	match m:
		"gun_charge": await _m_gun_charge()
		"laser_lane": await _m_laser_lane()
		"missile_weave": await _m_missile_weave()
		"cannon_skirmish": await _m_cannon_skirmish()
		"missile_barrage": await _m_missile_barrage()
		"missile_lane_strike": await _m_missile_lane_strike()
	_last_maneuver = m
	if not _dying and is_instance_valid(self):
		_go_idle()
	_busy = false


# From wave 2 (wave_idx 1) arm the interlude loop.
func on_wave_started(wave_idx: int) -> void:
	if wave_idx >= 1:
		_hazards_active = true
		if not _hazard_loop_started:
			_hazard_loop_started = true
			_hazard_loop()


# Survive-the-waves exit: withdraw off the bottom, no death/bounty. is_defeated() tells the gate to stop.
func retreat() -> void:
	if _dying:
		return
	_dying = true
	_hazards_active = false
	_set_wings(false)
	free_parts()
	_fly_dir = Vector2.DOWN
	_tgt_heading = _heading_for(Vector2.DOWN)
	_tgt_depth = 0.0
	_tgt_mode = M_THROUGH
	await _paced(2.6).timeout
	if is_instance_valid(self):
		queue_free()


func is_defeated() -> bool:
	return _dying


# ---- Maneuver selection -------------------------------------------------

func _pick_maneuver() -> String:
	var pool: Array = []
	if _guns_any_alive():
		pool.append("gun_charge")
		pool.append("cannon_skirmish")
	if _missiles_ok:
		pool.append("missile_weave")
	if _wings_alive():
		pool.append("laser_lane")
	if pool.is_empty():
		pool.append("gun_charge")   # weaponless → still make a threatening pass
	if pool.size() > 1 and _last_maneuver in pool:
		pool.erase(_last_maneuver)
	return pool[randi() % pool.size()]


func _guns_any_alive() -> bool:
	return _cannon_l or _cannon_r or _muzzle_l or _muzzle_r


func _rand_side() -> int:
	_side_flip = 1 - _side_flip
	return _side_flip


# ---- Between-wave maneuvers ---------------------------------------------

# Arrive centre lane facing down, hold, fire the cannons + muzzles GUN_VOLLEYS times, then rush down the
# middle line and exit.
func _m_gun_charge() -> void:
	_teleport(Vector2(_center_x(), -240.0), _heading_for(Vector2.DOWN), 0.0)
	_guns_firing = true   # the _process cadence sprays cannons+muzzles the whole time it's on-screen
	await _fly_to(Vector2(_center_x(), ARRIVE_Y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok():
		_guns_firing = false
		return
	await _paced(float(GUN_VOLLEYS) * GUN_BEAT).timeout   # hold in the lane, guns hot
	# Rush straight down the middle, still firing → past the player, FULLY off the bottom.
	await _fly_off(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, RUSH_DUR)
	_guns_firing = false


# Arrive centre lane; if a wing cannon lives, rake its beams down the lane, then fly down it.
func _m_laser_lane() -> void:
	if not _wings_alive():
		await _m_gun_charge()   # nothing to fire → fall back
		return
	_teleport(Vector2(_center_x(), -240.0), _heading_for(Vector2.DOWN), 0.0)
	_guns_firing = true   # cannons spray on the way in; the wing beams are the feature
	await _fly_to(Vector2(_center_x(), ARRIVE_Y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok():
		_guns_firing = false
		return
	_set_wings(true)
	await _paced(WING_BEAM_HOLD).timeout
	_set_wings(false)
	if not _maneuver_ok():
		_guns_firing = false
		return
	await _fly_off(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, RUSH_DUR)
	_guns_firing = false


# Arrive centre lane, open the missile bay, fire a homing salvo, close, then WEAVE off into an edge lane.
func _m_missile_weave() -> void:
	_teleport(Vector2(_center_x(), -240.0), _heading_for(Vector2.DOWN), 0.0)
	_guns_firing = true
	await _fly_to(Vector2(_center_x(), ARRIVE_Y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok():
		_guns_firing = false
		return
	await _open_missile_bay()
	if not _maneuver_ok():
		_guns_firing = false
		return
	await _fire_homing_salvo()
	await _close_missile_bay()
	if not _maneuver_ok():
		_guns_firing = false
		return
	# Weave off: thrust down AND toward an edge lane (a diagonal strafe exit), guns still hot.
	var side: int = _rand_side()
	var lateral: float = -1.0 if side == 0 else 1.0
	var weave_dir := Vector2(lateral, 1.4).normalized()
	await _fly_off(weave_dir, _heading_for(Vector2.DOWN), 0.0, RUSH_DUR)
	_guns_firing = false


# Arrive centre lane, fire a cannon burst, then oscillate centre ↔ a side lane firing a burst at each stop.
# After the first cycle (stop ≥ 2) it adds a MISSILE burst to every OTHER cannon burst.
func _m_cannon_skirmish() -> void:
	_teleport(Vector2(_center_x(), -240.0), _heading_for(Vector2.DOWN), 0.0)
	await _fly_to(Vector2(_center_x(), ARRIVE_Y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok(): return
	var side: int = 0
	var bay_open: bool = false
	for stop in SKIRMISH_STOPS:
		if not _maneuver_ok(): break
		# Even stop = centre; odd stop = a side (alternating left/right).
		var tx: float = _center_x()
		if stop % 2 == 1:
			tx = _center_x() + (SKIRMISH_SLIDE_X if side == 1 else -SKIRMISH_SLIDE_X)
			side = 1 - side
		await _fly_to(Vector2(tx, ARRIVE_Y), _heading_for(Vector2.DOWN), 0.0)
		if not _maneuver_ok(): break
		await _settle(0.4)
		# After the first cycle, every OTHER burst also fires missiles.
		var with_missiles: bool = stop >= 2 and (stop % 2 == 0)
		if with_missiles and not bay_open:
			await _open_missile_bay()
			bay_open = true
		await _skirmish_burst(with_missiles)
	if bay_open:
		await _close_missile_bay()
	if not _maneuver_ok(): return
	await _fly_off(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, RUSH_DUR)


# One skirmish stop: a quick cannon burst (SKIRMISH_BURST_SHOTS volleys), optionally followed by a small
# muzzle-cycled missile burst.
func _skirmish_burst(with_missiles: bool) -> void:
	for i in SKIRMISH_BURST_SHOTS:
		if not _maneuver_ok():
			return
		_fire_gun_volley()
		await _paced(SKIRMISH_BURST_GAP).timeout
	if with_missiles and _maneuver_ok():
		await _fire_homing_salvo(SKIRMISH_MISSILES)


# ---- During-wave interludes ---------------------------------------------

func _hazard_loop() -> void:
	while is_instance_valid(self) and not _dying:
		await _paced(randf_range(HAZARD_MIN_GAP, HAZARD_MAX_GAP)).timeout
		if _dying:
			return
		if not _hazards_active or _busy:
			continue
		var interlude: String = _pick_interlude()
		if interlude != "":
			await _run_maneuver(interlude)


func _pick_interlude() -> String:
	if not _missiles_ok:
		return ""   # both interludes are missile hazards — nothing to do once the missiles are gone
	var pool: Array = ["missile_barrage", "missile_lane_strike"]
	return pool[randi() % pool.size()]


# Missile-cruiser style: park in the bg, lob a salvo of MISSILE_SALVO missiles up into the play area with
# FRIENDLY FIRE (hits the player AND enemies). Uses the shared MissileSalvo.
func _m_missile_barrage() -> void:
	_barrage_passes += 1
	var salvos: int = clampi(_barrage_passes, 1, 5)   # one more salvo per pass (like the lane hazard's lanes), capped
	_teleport(Vector2(_center_x(), -240.0), _heading_for(Vector2.DOWN), 1.0)
	await _fly_to(Vector2(_center_x(), PARK_Y), _heading_for(Vector2.DOWN), 1.0)
	if not _maneuver_ok(): return
	await _settle()
	await _open_missile_bay()
	if not _maneuver_ok(): return
	var launchers := _launcher_markers()
	var launch_cb := func(i: int) -> Vector2:
		if launchers.is_empty():
			return global_position
		return (launchers[i % launchers.size()] as Node2D).global_position
	for s in salvos:
		if not _maneuver_ok(): break
		await MissileSalvo.run_salvo(self, _world(), {
			"zone_count": MISSILE_SALVO,
			"telegraph_time": 1.1,
			"missile_travel_time": 0.9,
			"fuse_time": 0.35,
			"aoe_radius": 26.0,
			"launch_stagger": 0.14,
			"zone_y_min": 60.0,
			"zone_y_max": 240.0,
			"launch": launch_cb,
			"launch_forward": Vector2(0, 1),
			"launch_forward_dist": 22.0,
			"friendly_fire": true,
			"ff_owner": self,
		})
		if s < salvos - 1:
			await _paced(BARRAGE_SALVO_GAP).timeout   # 2s: end of one salvo → next salvo's telegraph
	await _close_missile_bay()
	if not _maneuver_ok(): return
	await _fly_off(Vector2.DOWN, _heading_for(Vector2.DOWN), 1.0, RUSH_DUR)


# Mark LANE_STRIKE_SPOTS non-overlapping spots down each chosen lane; after a telegraph, missiles STREAK IN
# from the nearest screen edge + explode (friendly fire). +1 lane per pass, capped so ≥1 lane stays free.
func _m_missile_lane_strike() -> void:
	_lane_strike_passes += 1
	var n_lanes: int = clampi(_lane_strike_passes, 1, mini(5, Lanes.COUNT - 1))
	var lanes := _pick_lanes(n_lanes)
	# The boss STAYS OFF-SCREEN for this hazard (Roman 2026-07-07) — the missiles streak in from the
	# screen edges, so it never comes on-screen. No fly-in / bay anim / fly-off.
	_teleport(Vector2(_center_x(), -320.0), _heading_for(Vector2.DOWN), 1.0)
	var world: Node = _world()
	if world != null:
		# Phase 1 — telegraph every mark.
		var strikes: Array = []
		for lane in lanes:
			var lx: float = Lanes.lane_center(lane)
			var from_left: bool = lx < Playfield.CENTER.x
			var edge_x: float = (Playfield.X_MIN - 24.0) if from_left else (Playfield.X_MAX + 24.0)
			for i in LANE_STRIKE_SPOTS:
				var yy: float = lerpf(56.0, 240.0, float(i) / float(maxi(1, LANE_STRIKE_SPOTS - 1)))
				var mark := Vector2(lx, yy)
				var tc = MissileSalvo.TelegraphCircle.new()
				tc.setup(mark, 15.0)
				world.add_child(tc)
				strikes.append({"from": Vector2(edge_x, yy), "to": mark, "tc": tc})
		await _paced(STRIKE_TELEGRAPH).timeout
		# Phase 2 — missiles streak in from the nearest edge (friendly fire).
		if _maneuver_ok():
			for s in strikes:
				var mi = MissileSalvo.Missile.new()
				mi.setup(s["from"], s["to"], 0.5, 0.08, 22.0, 1, s["tc"], Vector2(INF, INF), true, self)
				world.add_child(mi)
			await _paced(0.75).timeout
	# Already off-screen — no bay anim / fly-off; _run_maneuver's _go_idle keeps it parked.


func _pick_lanes(n: int) -> Array:
	var all: Array = []
	for i in Lanes.COUNT:
		all.append(i)
	all.shuffle()
	return all.slice(0, clampi(n, 0, all.size()))


# ---- Guns (cannons = bolts, muzzles = lasers) ---------------------------

func _fire_gun_volley() -> void:
	var dir: Vector2 = _nose_dir()   # forward = down the lane when facing the player
	# Each side's cannon + muzzle is disabled when that side's FENDER section is destroyed.
	if _cannon_l:
		var m := _body_marker("CannonL")
		if m != null: _fire_bullet(BV_Bolt, m.global_position, dir, "enemy_mg")
	if _cannon_r:
		var m := _body_marker("CannonR")
		if m != null: _fire_bullet(BV_Bolt, m.global_position, dir, "enemy_mg")
	if _muzzle_l:
		var m := _body_marker("MuzzleL")
		if m != null: _fire_bullet(BV_Laser, m.global_position, dir, "enemy_blaster")
	if _muzzle_r:
		var m := _body_marker("MuzzleR")
		if m != null: _fire_bullet(BV_Laser, m.global_position, dir, "enemy_blaster")


func _body_marker(mname: String) -> Node2D:
	var b := get_node_or_null("Body")
	if b == null:
		return null
	return b.get_node_or_null(mname) as Node2D


# Fire one CORPO bullet from `base_variant` (a family-tagged BulletVariant): swap it to the corporate skin
# (frame 2 = lime) via BulletCatalog, spawn its scene aimed along `dir`, then play the enemy muzzle flash +
# fire SFX (both were missing → the "no fire sounds / generic bullets" bug).
func _fire_bullet(base_variant, from: Vector2, dir: Vector2, sfx_kind: String) -> void:
	var world: Node = _world()
	if base_variant == null or world == null:
		return
	var bv = BulletCatalog.faction_variant(base_variant, CORP_SKIN)
	var scene: PackedScene = BulletCatalog.scene_for(bv)
	if scene == null:
		return
	var b = scene.instantiate()
	if "variant" in b:
		b.variant = bv
	if "target_group" in b:
		b.target_group = "player"
	if "velocity_dir" in b:
		b.velocity_dir = dir.normalized()
	world.add_child(b)
	if b.has_method("start"):
		b.start(from)
	MuzzleFx.play_enemy(from, dir, world)
	EnemySfx.play(get_tree().root, from, sfx_kind)


# ---- Missiles (homing weave salvo) --------------------------------------

func _launcher_markers() -> Array:
	return find_children("Launcher*", "Marker2D", true, false)


# Fire `count` homing missiles (default MISSILE_SALVO), CYCLING the launcher muzzles with MISSILE_SHOT_DELAY
# (0.25s) between shots — one after another, not all at once (Roman 2026-07-07). Awaitable.
func _fire_homing_salvo(count: int = -1) -> void:
	if not _missiles_ok:          # the missile section (hood→missiles) was destroyed
		return
	var world: Node = _world()
	if world == null:
		return
	var launchers := _launcher_markers()
	if launchers.is_empty():
		return
	var n: int = count if count > 0 else MISSILE_SALVO
	for i in n:
		if not _maneuver_ok():
			return
		var lm := launchers[i % launchers.size()] as Node2D   # cycle the muzzles
		var mi = DriftingMissile.instantiate()
		if "initial_dir" in mi:
			mi.initial_dir = Vector2(0, 1)   # down toward the player; homes after the drift
		world.add_child(mi)
		if mi.has_method("start"):
			mi.start(lm.global_position)
		MuzzleFx.play_enemy(lm.global_position, Vector2.DOWN, world)
		WeaponSfx.play(get_tree().root, lm.global_position, "missile")
		if i < n - 1:
			await _paced(MISSILE_SHOT_DELAY).timeout


# Body centre roughly within the screen (a small margin) — gates the on-screen gun spray.
func _body_on_screen() -> bool:
	var vp: Vector2 = get_viewport_rect().size
	var p: Vector2 = position
	return p.x > -30.0 and p.x < vp.x + 30.0 and p.y > -60.0 and p.y < vp.y + 60.0


# ---- Missile bay cover ---------------------------------------------------

func _reset_bay_visuals() -> void:
	if _missile_cover != null:
		_missile_cover.visible = true
		_missile_cover.frame = 0   # closed at rest


# Missile bay doors: MissileCover is an 8-frame open→close strip (frame 0 closed → last open).
func _open_missile_bay() -> void:
	if _missile_cover == null:
		return
	_missile_cover.visible = true
	await _tween_frames(_missile_cover, 0, _missile_cover.hframes - 1, 0.35)


func _close_missile_bay() -> void:
	if _missile_cover == null:
		return
	await _tween_frames(_missile_cover, _missile_cover.hframes - 1, 0, 0.35)   # back to closed (stays visible)


# Animate a Sprite2D's frame from `a` to `b` over `dur` (a visible door slide).
func _tween_frames(spr: Sprite2D, a: int, b: int, dur: float) -> void:
	var t: float = 0.0
	while _maneuver_ok() and t < dur and is_instance_valid(spr):
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		spr.frame = int(round(lerpf(float(a), float(b), clampf(t / dur, 0.0, 1.0))))
	if is_instance_valid(spr):
		spr.frame = b


# ---- Destructible-parts hook / death ------------------------------------

func _on_boss_death() -> void:
	free_parts()
