extends "res://scripts/enemies/bosses/physics_boss.gd"

# The ZEALOT BATTLESHIP — a wide zealot MEGA-BOSS whose fight is DIRECTOR-SYNCHRONIZED (Roman 2026-07-01,
# supersedes the earlier self-pacing pass-cycle). It is present from wave 1 but IDLES off-screen (safe /
# invisible) between attacks; the wave director (director.gd `boss_gate`) drains each wave, then awaits
# ONE of the boss's maneuvers before starting the next. From wave 3 on it also fires off-screen STAGE
# HAZARD lasers during the waves. Its main lane laser is FRIENDLY-FIRE — it blows up the player AND
# enemies alike (except the boss's own parts). The hull art faces UP (nose = local -Y), so
# `rotation = dir.angle() + PI/2` points the nose along travel.
#
# WIN (Roman: "either — parts OR waves"): destroy every part → dramatic death + bounty (boss kill); OR
# survive the ~5-6 waves → the boss makes a final maneuver and retreats. The boss is only VULNERABLE
# while a maneuver has it on-screen.
#
# MANEUVERS (director calls play_wave_maneuver between waves; picks one eligible, no immediate repeat):
#   Lane Hook Firecores  — bg edge lane up from behind → high hold → rotate-slide (pivot on the laser
#                          muzzle) into centre facing DOWN → fan firecores up into the play area, dive out.
#   Lane Hook Laser      — same entry; the main laser CHARGES during the rotate-slide, fires down the
#                          centre lane on arrival, then dives out (forces the player L/R). Needs main laser.
#   Lane Hook Blockade   — same entry; rotate-slide up HORIZONTAL at centre high hold with the fuller
#                          side facing down; turrets + that side's lasers rake down; rotate down, dive out.
#                          Side pick: most side-lasers → else most turrets → else the maneuver is skipped.
#   Lane Firecore Slide  — fg edge lane from the top → ~1/3 down → sidestep across, drop firecores at
#                          centre → continue down + exit.
#   Lane Laser Slide     — fg edge lane from the top → ~1/3 down charging → fire down its lane → sidestep
#                          across (the downward beam sweeps with it), cut at centre → down + exit. Needs main.
#
# STAGE HAZARDS (boss off-screen, wave 3+, main laser alive): a red-telegraphed main-laser beam down a
# lane (friendly fire); the SWEEP variant then pans the beam edge→centre as a moving hazard.
#
# DESTRUCTIBLE PARTS (the fight — the hull is pass-through/unhittable, see _ready):
#   - TURRETS: boss_part shells each carrying a bench-configurable EnemyTurret (see _build_turrets).
#   - LASERS: authored scene emitters — one MainLaser + four SideLaser* (boss_z_battleship_laser.gd);
#     the boss discovers them (_collect_lasers), tracks them as parts, and toggles firing per maneuver.
# Built on boss_base's destructible-parts API. Dev-launch (Combat Lab) / Enemy Bench.

const BossPart = preload("res://scripts/enemies/bosses/boss_part.gd")
const LaserScript = preload("res://scripts/enemies/bosses/boss_z_battleship_laser.gd")
const MountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")
const TurretTex = preload("res://graphics/enemies/zealot-tank-turret.png")
const BoltVariant = preload("res://data/bullets/bolt.tres")   # generic frame-reskin bolt (zealot colour via faction_skin)
const FactionsC = preload("res://scripts/levels/factions.gd")
const FirecoreHazard = preload("res://scenes/enemies/factions/zealot/firecore_hazard.tscn")
# MountBuilder + EngineFlare + the movement machinery are inherited (enemy_base / physics_boss); bare names below.

# THRUSTER LAYOUT (local coords, nose = -Y; plume_rotation = where the EngineFlare plume POINTS, i.e.
# opposite the thrust). Groups: main = rear forward; spos/sneg = side STRAFE jets (spos pushes local +x
# → left-flank jets w/ plume left; sneg pushes -x); ycw/yccw = the diagonal RCS pairs that yaw the hull;
# top = inner divers (into the background). Roman 2026-07-02 (see the reference sketch).
const THRUSTER_DEFS := [
	["main", Vector2(-32, 138), 0.0], ["main", Vector2(32, 138), 0.0],
	["spos", Vector2(-54, -28), 0.5 * PI], ["spos", Vector2(-54, 88), 0.5 * PI],
	["sneg", Vector2(54, -28), -0.5 * PI], ["sneg", Vector2(54, 88), -0.5 * PI],
	["ycw", Vector2(-46, -88), 0.5 * PI], ["ycw", Vector2(46, 122), -0.5 * PI],
	["yccw", Vector2(46, -88), -0.5 * PI], ["yccw", Vector2(-46, 122), 0.5 * PI],
	["top", Vector2(-13, -8), PI], ["top", Vector2(13, -8), PI],
	["top", Vector2(-13, 42), PI], ["top", Vector2(13, 42), PI],
]

# Firecore release scatter (Roman 2026-07-01): fling the cores outward in a fan around a base direction,
# then they settle into their normal drift. Fan angle is derived from each core's WORLD x-offset (not
# tree order) so both banks spread OUTWARD symmetrically — no reversed / twisted launch.
const FIRECORE_FAN_HALF_DEG := 65.0    # base half-fan (widened per salvo)
const FIRECORE_BURST_SPEED := 150.0    # more energy → spreads further into the lanes (Roman 2026-07-02)
const FIRECORE_MAX_SALVOS := 5         # cap on the per-pass salvo count
const FIRECORE_SALVO_GAP := 0.3        # beat between salvos in a volley
const FIRECORE_FAN_STEP := 9.0         # each successive salvo widens the fan by this (deg), capped
const FIRECORE_FAN_MAX := 88.0
# Each SUBSEQUENT salvo launches slower (Roman 2026-07-02) so the salvos land at different depths — more
# separated + covering more area — instead of clumping at one range.
const FIRECORE_SALVO_SPEED_MULT := 0.72   # salvo k speed = BURST_SPEED * MULT^k
const FIRECORE_SALVO_SPEED_MIN := 45.0

const TURRET_HP := 64   # Roman 2026-07-01: turrets + side lasers cut to 64
const TURRET_HITBOX := Vector2(16, 16)
const HAZARD_MUZZLE_Y := 170.0   # off-screen ABOVE: -HAZARD_MUZZLE_Y puts the body off-top, muzzle near y=0

# MOVEMENT — a physics-inspired THRUST-DRIVEN rigid body (Roman 2026-07-02, replaces the nose-pivot). The
# ship has momentum: MAIN thrust pushes FORWARD ONLY (no reverse) along the nose; RCS torque swings it
# about its centre of mass; inner "top" thrusters dive it into the background (spring-restored to the
# fore). Station-keeping trim (LIN/ANG_DAMP) bleeds momentum so it always eases to a controllable stop.
# @export so the Battleship Lab live-tunes the heft; tune → Copy GDScript → paste this block back.
@export var HIGH_HOLD_Y: float = -12.0       # facing-down hold-Y for the CENTRE. The hull is 316px (taller
                                             # than the 270 playspace), so a small/negative value pins the
                                             # ship's mid-point at the TOP (rear off-screen) → nose ~mid,
                                             # bottom half open for the player. Applies to nose-DOWN hooks + slides.
@export var BLOCKADE_Y: float = 55.0         # broadside hold-Y for the blockade. Sideways the hull is only 128
                                             # tall, so it sits LOWER than the nose-down hold — low enough its
                                             # turrets are on-screen to fire/be shot, high enough to keep the
                                             # bottom half open (centre 55 ± 64 → ~-9..119, turrets visible).
# (the thrust MOVEMENT knobs MAIN_ACCEL … FACE_DAMP now live on physics_boss.gd — inherited @exports,
# still Lab-tunable + Copy-GDScript'd by their bare names.)
@export var BEAM_HOLD: float = 3.0           # hold in the centre lane while the main laser fires down it
@export var BLOCKADE_HOLD: float = 3.5       # hold horizontal while turrets + side lasers rake down
@export var HAZARD_MIN_GAP: float = 8.0      # stage-hazard cadence MIN (wave 3+)
@export var HAZARD_MAX_GAP: float = 14.0     # stage-hazard cadence MAX
@export var HAZARD_SWEEP_SPEED: float = 40.0 # off-screen sweep-beam pan speed

# (ARRIVE_TOL / FACE_TOL / FLY_TIMEOUT / UNDER_LAYER_Z / BG_TINT / BG_SCALE now live on physics_boss.gd.)

# --- runtime ---
var _turret_specs: Array = []      # kind==TURRET mount specs pulled out of `mounts` (built as destructibles)
var _turrets: Array = []           # live EnemyTurret refs (gated by _firing_enabled + on-screen)
var _lasers: Array = []            # all authored laser instances (main + side), registered as parts
var _side_lasers: Array = []       # the SideLaser* instances
var _main_laser = null             # the MainLaser instance
var _firing_enabled: bool = false  # turrets fire when true (set by the maneuver coroutines)
var _busy: bool = false            # a maneuver OR a hazard owns the boss right now (serializes the two)
var _hazards_active: bool = false  # stage hazards armed (from wave 3 = wave_idx 2)
var _hazard_loop_started: bool = false
var _last_maneuver: String = ""    # anti-immediate-repeat
var _side_flip: int = 0            # alternates the edge-lane side maneuvers start from
var _firecore_passes: int = 0      # firecore launches so far → salvo count (1 per pass, widening)
var _parts_max_total: int = 0      # sum of all part max_hp — drives the HP bar (the fight IS the parts)

# (the thrust-driven rigid-body state — _vel/_ang_vel/_depth/_cmd_*/_flares + the M_* pilot enum — now
# lives on physics_boss.gd; referenced here by bare name.)


func _ready() -> void:
	# Claim the TURRET mounts BEFORE super._ready() runs the base's _attach_mounts (else it would build
	# plain, non-destructible turrets from the same specs). Non-turret mounts stay in `mounts` for the base.
	_extract_turret_mounts()
	# Stats BEFORE super._ready() (boss convention). max_health is cosmetic — the hull is unhittable, so
	# the fight is the parts; kept non-zero for the shared boss HP-bar wiring.
	max_health = 1200
	bounty_value = 800
	display_scale = 1.0
	boss_hover_y = 48.0
	_initial_state = &"IDLE"    # the encounter SM just holds IDLE; maneuvers are driven externally (director)
	# Zealot boss — tag it so its cannon bolts frame-reskin to the zealot colour (frame 1).
	if not has_meta("faction_skin"):
		set_meta("faction_skin", FactionsC.Id.ZEALOT)
	super._ready()
	# The boss is fully script-driven (idle off-screen + tween-driven maneuvers) — keep _scripted_move on
	# so boss_base._process never applies its pattern/anchor/clamp (which would drag it into the playfield).
	_scripted_move = true
	# Pass-through hull: bullets can't register on it, so the turrets + lasers are the only targets.
	monitorable = false
	# UNDER-LAYER (Roman 2026-07-01): the whole boss + its children draw at z_index UNDER_LAYER_Z. The
	# parallax is on negative CanvasLayers, so a negative z in the world canvas still renders IN FRONT of
	# it — but BEHIND the player, its z=-1 engine trail, and bullets. Its parts/firecores inherit it
	# (z_as_relative); the beams' own z lifts them over. The body sprites are pinned absolutely below.
	z_index = UNDER_LAYER_Z
	_pin_body_under_layer()
	# Disable the HULL's own collision shape so nothing on the body intercepts player shots — the ONLY
	# hittable targets are the turret/laser parts (Roman 2026-07-02). monitorable=false already hides the
	# hull from detection; this makes it explicit + covers any shapecast-style bullet.
	for c in get_children():
		if (c is CollisionShape2D or c is CollisionPolygon2D) and "disabled" in c:
			c.disabled = true
	_build_turrets()
	_collect_lasers()
	_fix_firecore_sorting()
	_build_thruster_flares()
	# HP bar reflects TOTAL part HP (the hull is unhittable — the fight is destroying the parts), so it
	# drops meaningfully per turret/laser instead of barely moving. Overrides the cosmetic 1200.
	_parts_max_total = 0
	for p in live_parts():
		if "max_hp" in p:
			_parts_max_total += int(p.max_hp)
	if _parts_max_total > 0:
		max_health = _parts_max_total
		health = _parts_max_total
		health_changed.emit(health, max_health)
	# NOTE: no auto-idle here — start(pos) just places the boss (main.gd passes an off-screen pos for
	# production; the Enemy Bench passes an on-screen pos so its parts are visible/tunable). The off-screen
	# IDLE park (_go_idle) is a BETWEEN-maneuvers concept, driven by play_wave_maneuver / the hazards.


# The decorative FireCore cores are authored with z_index=1 so they draw over the hull — but z_index is
# GLOBAL within the canvas, so at mid-depth they'd still sort OVER the player. Drop them to z_index 0 and
# move them just after the GlowMask in tree order, so they draw over the hull (tree order) but under the
# player + bullets (Roman 2026-07-01).
func _fix_firecore_sorting() -> void:
	var gm := get_node_or_null("GlowMask")
	var base_idx: int = gm.get_index() if gm != null else 0
	for core in find_children("FireCore*", "", false, false):
		if core is CanvasItem:
			(core as CanvasItem).z_index = 0
			move_child(core, base_idx + 1)


# No hull-mounted gun — the turrets + lasers do all the firing.
func _on_shoot_timer_timeout() -> void:
	pass


# The battleship doesn't use engine trails/flames (Roman 2026-07-01) — suppress the base's automatic
# Engine* trail attach (enemy_base._attach_engine_trail runs in super._ready()).
func _attach_engine_trail() -> void:
	pass


# ---- physics_boss hooks -------------------------------------------------

# Our thruster geometry (physics_boss reads this to build the flares).
func _thruster_defs() -> Array:
	return THRUSTER_DEFS


# Cut all weapons when the boss parks off-screen (physics_boss._go_idle calls this).
func _stop_firing() -> void:
	_firing_enabled = false
	_set_side_lasers(false)
	_set_main_laser(false)


# ---- Part construction --------------------------------------------------

func _extract_turret_mounts() -> void:
	_turret_specs = []
	if mounts == null or mounts.is_empty():
		return
	var kept: Array = []
	for s in mounts:
		if s != null and "kind" in s and int(s.kind) == MountSpecC.Kind.TURRET:
			_turret_specs.append(s)
		else:
			kept.append(s)
	mounts = kept


# Destructible turret per Turret* marker, built from a turret spec (a configured mount, else the default).
func _build_turrets() -> void:
	var specs: Array = _turret_specs if not _turret_specs.is_empty() else [_default_turret_spec()]
	for spec in specs:
		var pattern: String = String(spec.marker) if String(spec.marker) != "" else "Turret*"
		for mount in find_children(pattern, "Marker2D", true, false):
			_build_destructible_turret(mount as Node2D, spec)


# A boss_part shell carrying a bench-configurable EnemyTurret (reuses MountBuilder for the config).
func _build_destructible_turret(mount: Node2D, spec) -> void:
	var shell = BossPart.new()
	shell.setup(self, TURRET_HP)
	shell.leave_trail = false        # the boss spawns its own rearward torch+smoke wreck (see _on_part_lost)
	shell.wants_damage_tells = true  # damage overlay + spark trail from 50% HP (boss_part)
	shell.smart_bomb_cap = 20        # decent smart-bomb damage, but not a one-shot
	shell.set_meta("kind", "turret")
	shell.set_meta("mount", mount)
	shell.add_child(_hitbox(TURRET_HITBOX))
	# Build the EnemyTurret (+ barrel) into the shell BEFORE it enters the tree, so the shell's _ready
	# damage-tell install finds the barrel sprite to drive the overlay/sparks off.
	MountBuilder._build_turret(self, spec, shell)
	mount.add_child(shell)
	for c in shell.get_children():
		if c is EnemyTurret:
			(c as EnemyTurret).enabled = false      # gated by _update_turret_gate
			_turrets.append(c)
			break
	register_part(shell)


# The out-of-the-box turret weapon when nothing is authored in `mounts`. The Bench overrides via a turret
# mount or the Turret-payload dropdown.
func _default_turret_spec():
	var s = MountSpecC.new()
	s.kind = MountSpecC.Kind.TURRET
	s.marker = "Turret*"
	s.payload = BoltVariant
	s.fire_interval_min = 1.8
	s.fire_interval_max = 2.6
	s.aim_tolerance_deg = 16.0
	s.rotation_speed = 3.2
	s.recoil_frames = 3
	s.turret_texture = TurretTex
	s.turret_hframes = 3
	return s


# Discover the authored laser scene instances (MainLaser + SideLaser*), register them as destructible
# parts, wire the friendly-fire owner, and flip the destroyed sprite on the "back" (…B) side laser of
# each pair so wrecked pairs differ.
func _collect_lasers() -> void:
	_lasers = []
	_side_lasers = []
	_main_laser = null
	for n in find_children("*", "", true, false):
		if n.get_script() != LaserScript:
			continue
		if n.has_method("set_boss"):
			n.set_boss(self)   # wires the friendly-fire exclusion owner (the main laser ignores our own parts)
		register_part(n)
		_lasers.append(n)
		if String(n.beam_kind) == "main":
			_main_laser = n
		else:
			_side_lasers.append(n)
			n.flip_when_destroyed = String(n.name).ends_with("B")


func _hitbox(sz: Vector2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = sz
	cs.shape = shape
	return cs


# ---- State graph --------------------------------------------------------

# One benign IDLE state so the base's encounter SM is "active" (skips the legacy HP-ladder phases). We
# never transition — maneuvers are driven imperatively by the director via play_wave_maneuver.
func _build_states() -> void:
	add_state(&"IDLE")


func _state_enter(_state_name: StringName) -> void:
	pass


# ---- Director API (called by director.gd boss_gate) ---------------------

# Play ONE maneuver and return when the boss is back off-screen/idle. Awaited by the director between
# waves (and once more, with wave_idx=-1, after the last wave). Serialized against the hazard loop.
func play_wave_maneuver(_wave_idx: int = 0) -> void:
	await _run_maneuver(_pick_maneuver())


# Dev (Battleship Lab): play a SPECIFIC maneuver or hazard on demand.
func play_named_maneuver(name: String) -> void:
	await _run_maneuver(name)


# Names the Lab can trigger (order = its button row).
const MANEUVER_NAMES := ["hook_firecores", "hook_laser", "hook_blockade", "firecore_slide", "laser_slide",
	"lane_laser", "hazard_lane_laser", "hazard_sweep"]


# Run one named maneuver/hazard, serialized against any other (the wave gate + the hazard loop share
# this), returning once the boss is back off-screen/idle.
func _run_maneuver(m: String) -> void:
	if _dying or not is_instance_valid(self):
		return
	# Wait out anything currently running so the two never fight over the boss's position.
	while _busy and not _dying:
		await get_tree().process_frame
	if _dying:
		return
	_busy = true
	match m:
		"hook_firecores": await _m_lane_hook_firecores()
		"hook_laser": await _m_lane_hook_laser()
		"hook_blockade": await _m_lane_hook_blockade()
		"firecore_slide": await _m_lane_firecore_slide()
		"laser_slide": await _m_lane_laser_slide()
		"lane_laser": await _m_lane_laser()
		"hazard_lane_laser": await _hazard_lane_laser()
		"hazard_sweep": await _hazard_lane_laser_sweep()
	_last_maneuver = m
	if not _dying and is_instance_valid(self):
		_go_idle()
	_busy = false


# The director tells us a wave began; from wave 3 (wave_idx 2) we arm the stage-hazard loop.
func on_wave_started(wave_idx: int) -> void:
	if wave_idx >= 2:
		_hazards_active = true
		if not _hazard_loop_started:
			_hazard_loop_started = true
			_hazard_loop()


# Survive-the-waves exit: stop everything and withdraw off the bottom, then free. NO death/bounty (the
# player didn't kill it). Reports is_defeated so the gate stops driving us.
func retreat() -> void:
	if _dying:
		return
	_dying = true
	_hazards_active = false
	_firing_enabled = false
	_set_side_lasers(false)
	_set_main_laser(false)
	free_parts()
	# Burn away off the bottom — the integrator keeps flying it even though _dying is set.
	_fly_dir = Vector2.DOWN
	_tgt_heading = _heading_for(Vector2.DOWN)
	_tgt_depth = 0.0
	_tgt_mode = M_THROUGH
	await _paced(2.6).timeout
	if is_instance_valid(self):
		queue_free()


# True once the boss has begun dying OR retreating — the director's gate stops driving it.
func is_defeated() -> bool:
	return _dying


# ---- Maneuver selection -------------------------------------------------

func _pick_maneuver() -> String:
	var pool: Array = ["hook_firecores", "firecore_slide"]   # always available (no laser needed)
	if _main_laser_alive():
		pool.append("hook_laser")
		pool.append("laser_slide")
		pool.append("lane_laser")
	if _blockade_side() >= 0:
		pool.append("hook_blockade")
	# Avoid an immediate repeat when there's an alternative.
	if pool.size() > 1 and _last_maneuver in pool:
		pool.erase(_last_maneuver)
	if pool.is_empty():
		return "firecore_slide"
	return pool[randi() % pool.size()]


func _main_laser_alive() -> bool:
	return _main_laser != null and is_instance_valid(_main_laser) \
		and not (_main_laser.has_method("is_destroyed") and _main_laser.is_destroyed())


# Which side to blockade with: the side with the MOST live side-lasers; on a tie / none, the side with
# more live turrets; if neither side has any side-laser or turret, -1 (don't blockade). 0 = left (local
# x<0), 1 = right (local x>0).
func _blockade_side() -> int:
	var sl_l: int = 0; var sl_r: int = 0; var tu_l: int = 0; var tu_r: int = 0
	for p in live_parts():
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		var lx: float = to_local((p as Node2D).global_position).x
		var is_side_laser: bool = p.get_script() == LaserScript and "beam_kind" in p and String(p.beam_kind) == "side"
		var is_turret: bool = p.has_meta("kind") and String(p.get_meta("kind")) == "turret"
		if is_side_laser:
			if lx < 0.0: sl_l += 1
			else: sl_r += 1
		elif is_turret:
			if lx < 0.0: tu_l += 1
			else: tu_r += 1
	if sl_l == 0 and sl_r == 0 and tu_l == 0 and tu_r == 0:
		return -1
	if sl_l != sl_r:
		return 0 if sl_l > sl_r else 1
	if tu_l != tu_r:
		return 0 if tu_l > tu_r else 1
	return 0   # full tie → left


func _rand_side() -> int:
	_side_flip = 1 - _side_flip
	return _side_flip


# ---- Maneuvers ----------------------------------------------------------

# bg edge lane up from behind → high hold → rotate-slide into centre facing DOWN → fan firecores UP into
# the play area while diving out the bottom.
func _m_lane_hook_firecores() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var ex: float = _edge_lane_x(_rand_side())
	_firing_enabled = false
	# Start in the deep BACKGROUND (depth 1 — stays faint/small), edge lane, below, facing up.
	_teleport(Vector2(ex, vp.y + 240.0), _heading_for(Vector2.UP), 1.0)
	await _fly_to(Vector2(ex, HIGH_HOLD_Y), _heading_for(Vector2.UP), 1.0)   # rise up the lane (bg)
	if not _maneuver_ok(): return
	await _fly_to(Vector2(_center_x(), HIGH_HOLD_Y), _heading_for(Vector2.DOWN), 1.0)   # swing to centre facing down (bg)
	if not _maneuver_ok(): return
	await _settle()   # finish the move BEFORE releasing (Roman 2026-07-02: cores were dropping mid-drift)
	if not _maneuver_ok(): return
	await _launch_firecore_salvos(0.5)   # emerge small from the distant boss, grow as they rise in (widening volley)
	await _fly_through(Vector2.DOWN, _heading_for(Vector2.DOWN), 1.0, 2.6)   # dive out (bg)


# As the firecore hook, but the main laser charges during the rotate-slide and fires down the centre lane
# on arrival, then the boss dives out (forcing the player left/right of the beam).
func _m_lane_hook_laser() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var ex: float = _edge_lane_x(_rand_side())
	_firing_enabled = false
	_teleport(Vector2(ex, vp.y + 240.0), _heading_for(Vector2.UP), 1.0)
	await _fly_to(Vector2(ex, HIGH_HOLD_Y), _heading_for(Vector2.UP), 1.0)   # rise up the lane (bg)
	if not _maneuver_ok(): return
	# Surface + swing to centre facing down, then SETTLE — only THEN charge + fire, so the beam fires
	# ONCE, cleanly down the centre lane (not a first shot while it's still turning into position).
	await _fly_to(Vector2(_center_x(), HIGH_HOLD_Y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok(): return
	await _settle()
	if not _maneuver_ok(): return
	_set_main_laser(true)
	await _paced(BEAM_HOLD).timeout
	_set_main_laser(false)   # graceful shrink+flicker out
	if not _maneuver_ok(): return
	_dive(1.0)   # recede back into the background
	await _fly_through(Vector2.DOWN, _heading_for(Vector2.DOWN), 1.0, 2.6)


# bg edge lane up from behind → high hold → rotate-slide up HORIZONTAL at centre high hold with the
# fuller side facing down; turrets + that side's lasers rake down; then pivot to nose-down, drop into the
# background and dive out.
func _m_lane_hook_blockade() -> void:
	var side: int = _blockade_side()
	if side < 0:
		await _m_lane_hook_firecores()   # nothing left to blockade with → fall back to a firecore hook
		return
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = _center_x()
	_firing_enabled = false
	var rot_horizontal: float = (-PI * 0.5) if side == 0 else (PI * 0.5)   # the fuller side faces DOWN
	# Rise up the CENTRE lane facing up (bg), then surface + rotate IN PLACE to horizontal — brings the
	# fuller side to bear with a single 90° turn, no sideways fly (Roman 2026-07-02: fixes the setup delay).
	_teleport(Vector2(cx, vp.y + 240.0), _heading_for(Vector2.UP), 1.0)
	await _fly_to(Vector2(cx, BLOCKADE_Y), _heading_for(Vector2.UP), 1.0)   # broadside sits lower than nose-down holds
	if not _maneuver_ok(): return
	_dive(0.0)   # surface
	await _face(rot_horizontal)   # rotate in place to horizontal
	if not _maneuver_ok(): return
	# Rake: turrets fire + the down-facing side's lasers fire down the play area.
	_firing_enabled = true
	_activate_blockade_lasers(side)
	await _paced(BLOCKADE_HOLD).timeout
	_firing_enabled = false
	_set_side_lasers(false)
	if not _maneuver_ok(): return
	# Dive out STILL HORIZONTAL — strafe straight down (side jets) instead of rotating back to nose-down,
	# so the blockade only ever rotates the 90° needed to bring the fuller side to bear (Roman 2026-07-02).
	_dive(1.0)
	await _fly_through(Vector2.DOWN, rot_horizontal, 1.0, 2.6)


# fg edge lane from the top → ~1/3 down → sidestep across, DROPPING a firecore in EACH lane it passes
# (a descending wall) → down + exit. Faces DOWN throughout (a lateral sidestep, not a turn).
func _m_lane_firecore_slide() -> void:
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var ox: float = _edge_lane_x(1 - side)
	var third_y: float = HIGH_HOLD_Y   # slide/fire at the high hold (top) so the bottom half stays open
	_firing_enabled = false
	# Foreground, top of the edge lane, facing down.
	_teleport(Vector2(ex, -240.0), _heading_for(Vector2.DOWN), 0.0)
	await _fly_to(Vector2(ex, third_y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok(): return
	await _slide_dropping_firecores(ox, third_y)   # strafe across, dropping a firecore at each lane spot
	if not _maneuver_ok(): return
	await _fly_through(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, 2.6)   # exit off the bottom


# fg edge lane from the top → ~1/3 down charging → fire down its lane → sidestep across (the downward
# beam sweeps with it), cut at centre → to the opposite lane → down + exit.
func _m_lane_laser_slide() -> void:
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var ox: float = _edge_lane_x(1 - side)
	var third_y: float = HIGH_HOLD_Y   # slide/fire at the high hold (top) so the bottom half stays open
	_firing_enabled = false
	_teleport(Vector2(ex, -240.0), _heading_for(Vector2.DOWN), 0.0)
	_set_main_laser(true)   # charge during the descent
	await _fly_to(Vector2(ex, third_y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	# Bank across to centre — the firing beam sweeps + banks with the hull, then cut it at centre.
	await _fly_to(Vector2(_center_x(), third_y), _heading_for(Vector2.DOWN), 0.0)
	_set_main_laser(false)
	if not _maneuver_ok(): return
	await _fly_to(Vector2(ox, third_y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok(): return
	await _fly_through(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, 2.6)


# Like the laser slide but COMMITS to ONE lane (any lane): descend into it, fire straight down it (no
# sweep), then continue down + exit. Needs the main laser.
func _m_lane_laser() -> void:
	var lane: int = randi() % Lanes.COUNT
	var lx: float = Lanes.lane_center(lane)
	var third_y: float = HIGH_HOLD_Y   # slide/fire at the high hold (top) so the bottom half stays open
	_firing_enabled = false
	_teleport(Vector2(lx, -240.0), _heading_for(Vector2.DOWN), 0.0)   # fg, top of the CHOSEN lane, facing down
	_set_main_laser(true)   # charge during the descent
	await _fly_to(Vector2(lx, third_y), _heading_for(Vector2.DOWN), 0.0)
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	await _settle()   # commit to the lane — hold it while the beam fires straight down (no sweep)
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	await _paced(BEAM_HOLD).timeout
	_set_main_laser(false)   # graceful shrink+flicker out
	if not _maneuver_ok(): return
	await _fly_through(Vector2.DOWN, _heading_for(Vector2.DOWN), 0.0, 2.6)   # continue down + exit


# Slide across to `to_x` at latitude `y`, facing down, DROPPING one firecore straight down in each lane
# the ship passes over (Roman 2026-07-02) — a descending wall. Sheds a decorative core per drop.
func _slide_dropping_firecores(to_x: float, y: float) -> void:
	_tgt_pos = Vector2(to_x, y)
	_tgt_heading = _heading_for(Vector2.DOWN)
	_tgt_depth = 0.0
	_tgt_mode = M_FLY
	var dropped: Dictionary = {}
	var t: float = 0.0
	while _maneuver_ok() and t < FLY_TIMEOUT:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		var lane: int = Lanes.nearest_lane(position.x)
		if not dropped.has(lane) and absf(position.x - Lanes.lane_center(lane)) < 10.0:
			dropped[lane] = true
			_drop_firecore_at(Vector2(Lanes.lane_center(lane), position.y))
		if position.distance_to(_tgt_pos) < ARRIVE_TOL:
			var flane: int = Lanes.nearest_lane(to_x)
			if not dropped.has(flane):
				_drop_firecore_at(Vector2(Lanes.lane_center(flane), position.y))
			return


# Drop a single firecore straight down at `pos` (no burst) + shed one decorative hull core.
func _drop_firecore_at(pos: Vector2) -> void:
	var world: Node = _world()
	if FirecoreHazard == null or world == null:
		return
	var fc = FirecoreHazard.instantiate()
	world.add_child(fc)
	if fc is CanvasItem:
		(fc as CanvasItem).z_index = UNDER_LAYER_Z
	(fc as Node2D).global_position = pos
	if fc.has_method("start"):
		fc.start(pos)
	for core in find_children("FireCore*", "", false, false):
		if core is CanvasItem and (core as CanvasItem).visible:
			(core as CanvasItem).visible = false
			break


# ---- Stage hazards (wave 3+, boss off-screen) ---------------------------

# Periodic off-screen lane lasers while hazards are armed and the boss isn't mid-maneuver. Needs the main
# laser alive (main-laser maneuvers/hazards are impossible once it's destroyed).
func _hazard_loop() -> void:
	while is_instance_valid(self) and not _dying:
		await _paced(randf_range(HAZARD_MIN_GAP, HAZARD_MAX_GAP)).timeout
		if _dying:
			return
		if not _hazards_active or _busy or not _main_laser_alive():
			continue
		_busy = true
		if randi() % 2 == 0:
			await _hazard_lane_laser()
		else:
			await _hazard_lane_laser_sweep()
		_busy = false


# Position the boss off-screen ABOVE a lane (facing down) so the muzzle just clears the top, fire the
# main laser DOWN the lane (friendly fire: player AND enemies), then return to idle.
func _hazard_lane_laser() -> void:
	var lane: int = randi() % Lanes.COUNT
	var lx: float = Lanes.lane_center(lane)
	# Off-screen ABOVE the lane, facing down, foreground scale (so the beam geometry is full-size). Teleport
	# (M_IDLE, zero velocity) — the hazard is off-screen, no physics needed.
	_teleport(Vector2(lx, -HAZARD_MUZZLE_Y), _heading_for(Vector2.DOWN), 0.0)
	_set_main_laser(true)
	var dur: float = _main_laser_duration()
	if dur > 0.0:
		await _paced(dur).timeout
	_set_main_laser(false)
	if is_instance_valid(self) and not _dying:
		_go_idle()


# As the lane laser, but after the warning + fire it PANS the beam from an edge lane toward the centre
# (translating the off-screen boss so the downward beam sweeps across lanes).
func _hazard_lane_laser_sweep() -> void:
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var cx: float = _center_x()
	_teleport(Vector2(ex, -HAZARD_MUZZLE_Y), _heading_for(Vector2.DOWN), 0.0)
	_set_main_laser(true)
	await _paced(_main_laser_windup()).timeout   # hold the red warning at the edge lane
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	# Pan the off-screen boss edge→centre so the downward beam sweeps across the lanes. Manual x-lerp (the
	# ship is idle/off-screen; the integrator holds velocity at 0, so it doesn't fight this).
	var pan_dur: float = absf(cx - ex) / maxf(HAZARD_SWEEP_SPEED, 1.0)
	var t: float = 0.0
	while _maneuver_ok() and t < pan_dur:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		position.x = lerpf(ex, cx, clampf(t / pan_dur, 0.0, 1.0))
	_set_main_laser(false)
	if is_instance_valid(self) and not _dying:
		_go_idle()


# ---- Thrust-driven rigid-body movement --------------------------------------------------------------
# The whole thrust locomotion + awaitable pilot primitives + thruster flares + depth shading now live on
# physics_boss.gd (extracted 2026-07-06). The battleship supplies its geometry via _thruster_defs() and
# stops its weapons via _stop_firing() (above); it calls the inherited _fly_to/_face/_fly_through/_settle/
# _dive/_teleport/_go_idle/_edge_lane_x/_center_x/_heading_for from its maneuvers.


# ---- Laser control (the authored scene emitters) ------------------------

func _set_main_laser(on: bool) -> void:
	if _main_laser != null and is_instance_valid(_main_laser):
		_main_laser.set_active(on)


# The main laser's full warn→fire→vanish cycle duration (0 if it's gone), so a hazard waits it out.
func _main_laser_duration() -> float:
	if _main_laser != null and is_instance_valid(_main_laser) and _main_laser.has_method("beam_duration") \
			and not (_main_laser.has_method("is_destroyed") and _main_laser.is_destroyed()):
		return float(_main_laser.beam_duration())
	return 0.0


# The main laser's windup (warning) duration, so the sweep hazard holds the red line before it pans.
func _main_laser_windup() -> float:
	if _main_laser != null and is_instance_valid(_main_laser) and _main_laser.has_method("beam_windup"):
		return float(_main_laser.beam_windup())
	return 1.2


func _set_side_lasers(on: bool) -> void:
	for l in _side_lasers:
		if is_instance_valid(l):
			l.set_active(on)


# Blockade: fire only the side lasers on the chosen physical side (local x<0 = left). The other side's
# lasers would fire off-screen, so leave them idle.
func _activate_blockade_lasers(side: int) -> void:
	for l in _side_lasers:
		if not is_instance_valid(l) or not (l is Node2D):
			continue
		var lx: float = (l as Node2D).position.x
		if (side == 0 and lx < 0.0) or (side == 1 and lx > 0.0):
			l.set_active(true)


# ---- Firecores ----------------------------------------------------------

# Release a drifting firecore hazard from each FireCore* core: scatter them in a FAN around `base_dir`
# (a decaying burst), after which each settles into its normal downward drift. `grow_from` <1 makes each
# ember START small and grow to full size as it rises into the foreground (the background hook release —
# the boss stays faint/distant while its firecores rise toward the player). Hide the spent decoration.
# Launch a WIDENING volley: 1 salvo on the first firecore pass, 2 on the second, 3 on the third … each
# salvo fanned wider than the last (Roman 2026-07-02), so coverage grows over the fight. Capped.
func _launch_firecore_salvos(grow_from: float = 1.0) -> void:
	_firecore_passes += 1
	var salvos: int = clampi(_firecore_passes, 1, FIRECORE_MAX_SALVOS)
	for k in salvos:
		if not _maneuver_ok():
			return
		var fan: float = minf(FIRECORE_FAN_MAX, FIRECORE_FAN_HALF_DEG + float(k) * FIRECORE_FAN_STEP)
		var speed: float = maxf(FIRECORE_SALVO_SPEED_MIN, FIRECORE_BURST_SPEED * pow(FIRECORE_SALVO_SPEED_MULT, float(k)))
		_release_firecores(Vector2.DOWN, grow_from, fan, speed)
		if k < salvos - 1:
			await _paced(FIRECORE_SALVO_GAP).timeout


# One salvo: a firecore from each FireCore* core, fanned OUTWARD by the core's WORLD x-offset from the
# ship centre (so left cores go down-left, right cores down-right — no reversed/twisted launch,
# independent of the hull's rotation). `grow_from` <1 makes them rise from small; `fan_half_deg` = spread.
func _release_firecores(base_dir: Vector2 = Vector2.DOWN, grow_from: float = 1.0, fan_half_deg: float = FIRECORE_FAN_HALF_DEG, burst_speed: float = FIRECORE_BURST_SPEED) -> void:
	var world: Node = _world()
	if FirecoreHazard == null or world == null:
		return
	var cores: Array = find_children("FireCore*", "", true, false)
	var bx: float = global_position.x
	var maxdx: float = 1.0
	for c in cores:
		if c is Node2D:
			maxdx = maxf(maxdx, absf((c as Node2D).global_position.x - bx))
	for core in cores:
		if not (core is Node2D):
			continue
		var fc = FirecoreHazard.instantiate()
		world.add_child(fc)
		if fc is CanvasItem:
			(fc as CanvasItem).z_index = UNDER_LAYER_Z   # mid-depth, behind the player (matches the ship)
		var pos: Vector2 = (core as Node2D).global_position
		(fc as Node2D).global_position = pos
		var frac: float = clampf((pos.x - bx) / maxdx, -1.0, 1.0)   # -1 world-left … +1 world-right
		var dir: Vector2 = base_dir.rotated(deg_to_rad(-frac * fan_half_deg))   # left→down-left, right→down-right
		if "burst_velocity" in fc:
			fc.burst_velocity = dir * burst_speed
		if "spawn_scale" in fc:
			fc.spawn_scale = grow_from
		if fc.has_method("start"):
			fc.start(pos)
		(core as CanvasItem).visible = false


# ---- Per-frame: turret gate ---------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)   # physics_boss: boss_base._process + _integrate_physics(delta)
	_update_turret_gate()
	_update_health_bar()


# Drive the shared boss HP bar off the LIVE aggregate part HP so it tracks cumulative turret + laser
# damage (each part's hp falls as it's shot; destroyed parts drop out of live_parts entirely).
func _update_health_bar() -> void:
	if _dying or _parts_max_total <= 0:
		return
	var cur: int = 0
	for p in live_parts():
		if not is_instance_valid(p) or not ("hp" in p):
			continue
		if "_destroyed" in p and p._destroyed:
			continue   # a wrecked laser HUSK (not freed) contributes 0
		cur += maxi(0, int(p.hp))
	if cur != health:
		health = cur
		health_changed.emit(health, max_health)


# Turrets fire only while _firing_enabled (a firing maneuver) AND fully on-screen (the ship is bigger
# than the viewport, so off-screen turrets on a moving pass hold fire).
func _update_turret_gate() -> void:
	var can_fire: bool = _firing_enabled and not _dying
	for t in _turrets:
		if is_instance_valid(t):
			(t as EnemyTurret).enabled = can_fire and _turret_on_screen(t)


func _turret_on_screen(tp: Node2D) -> bool:
	if not is_instance_valid(tp):
		return false
	var vp: Vector2 = get_viewport_rect().size
	var half: Vector2 = TURRET_HITBOX * 0.5
	var p: Vector2 = tp.global_position
	return p.x - half.x >= 0.0 and p.x + half.x <= vp.x and p.y - half.y >= 0.0 and p.y + half.y <= vp.y


func _onscreen_live_turrets() -> int:
	var n: int = 0
	for t in _turrets:
		if is_instance_valid(t) and _turret_on_screen(t):
			n += 1
	return n


# ---- Destructible-parts hook -------------------------------------------

# A turret / laser was destroyed: leave a torch + smoke wreck drifting toward the rear, and if EVERY
# destructible part is gone, the battleship is defeated → dramatic death (bounty + boss kill).
func _on_part_lost(part: Node) -> void:
	var host: Node = null
	if part != null and part.has_meta("mount"):
		host = part.get_meta("mount")   # turrets: the mount marker (the shell itself frees)
	elif part is Node2D:
		host = part                      # lasers: the wrecked husk stays in place
	if host is Node2D:
		_spawn_wreck_fx(to_local((host as Node2D).global_position))
	if not _dying and live_parts().is_empty():
		_death_sequence()


# All parts destroyed → the "parts" win. Stop firing, restore full colour so the death reads clean, then
# route through boss_base.explode() (the dramatic 7-blast cascade + bounty + Run.on_boss_defeated + free).
func _death_sequence() -> void:
	if _dying:
		return
	_hazards_active = false
	_firing_enabled = false
	_set_side_lasers(false)
	_set_main_laser(false)
	_depth = 0.0            # surface instantly so the death multi-blast reads at full colour / scale
	_depth_vel = 0.0
	_apply_depth()
	explode()   # boss_base: sets _dying, multi-blast, died.emit(bounty), on_boss_defeated, frees after ~1.3s


# A persistent torch flame + smoke column at a destroyed part's location, drifting toward the ship's REAR
# (local +X — the Engine markers). Parented to the boss so it rides + rotates with the hull.
func _spawn_wreck_fx(local_pos: Vector2) -> void:
	var fire := CPUParticles2D.new()
	fire.position = local_pos
	fire.amount = 14
	fire.lifetime = 0.5
	fire.local_coords = true
	fire.direction = Vector2(1, 0)          # toward the rear (+X local)
	fire.spread = 22.0
	fire.gravity = Vector2(70, 0)
	fire.initial_velocity_min = 20.0
	fire.initial_velocity_max = 46.0
	fire.scale_amount_min = 1.0
	fire.scale_amount_max = 2.2
	fire.color = Color(1.7, 0.95, 0.35, 0.95)   # HDR-warm → blooms
	fire.z_index = 2
	add_child(fire)
	var smoke := CPUParticles2D.new()
	smoke.position = local_pos
	smoke.amount = 18
	smoke.lifetime = 0.95
	smoke.local_coords = true
	smoke.direction = Vector2(1, 0)
	smoke.spread = 30.0
	smoke.gravity = Vector2(38, 0)
	smoke.initial_velocity_min = 10.0
	smoke.initial_velocity_max = 26.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.6
	smoke.color = Color(0.12, 0.12, 0.13, 0.85)
	smoke.z_index = 1
	add_child(smoke)


# ---- Cleanup ------------------------------------------------------------

func _on_boss_death() -> void:
	free_parts()
