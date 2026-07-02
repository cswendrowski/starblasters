extends "res://scripts/enemies/bosses/boss_base.gd"

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
const BoltVariant = preload("res://data/bullets/zealot_bolt.tres")
const FirecoreHazard = preload("res://scenes/enemies/factions/zealot/firecore_hazard.tscn")
# MountBuilder is an inherited const from enemy_base; referenced by its bare name below.

# Firecore release scatter (Roman 2026-07-01): fling the cores outward in a fan around a base direction,
# then they settle into their normal drift.
const FIRECORE_FAN_HALF_DEG := 55.0
const FIRECORE_BURST_SPEED := 90.0

const TURRET_HP := 64   # Roman 2026-07-01: turrets + side lasers cut to 64
const TURRET_HITBOX := Vector2(16, 16)
const HAZARD_MUZZLE_Y := 170.0   # off-screen ABOVE: -HAZARD_MUZZLE_Y puts the body off-top, muzzle near y=0

# MOVEMENT / TIMING KNOBS (Roman 2026-07-02) — @export so the Battleship Lab (scenes/dev/battleship_lab)
# can LIVE-TUNE the ponderous feel; kept UPPER_CASE so the maneuvers read them like the old consts. Tune
# in the Lab → Copy GDScript → paste this block back. Deliberately SLOW — a heavy, ponderous mega-boss.
@export var HIGH_HOLD_Y: float = 64.0        # the "high hold point" — where a hook maneuver comes to rest near the top
@export var HOOK_RISE_SPEED: float = 65.0    # coming up the edge lane from behind
@export var HOOK_DIVE_SPEED: float = 90.0    # diving out the bottom
@export var SLIDE_ENTER_SPEED: float = 55.0  # foreground entry from the top (also covers the laser windup)
@export var SLIDE_CROSS_SPEED: float = 60.0  # sidestepping across the play area
@export var SLIDE_EXIT_SPEED: float = 90.0   # exiting off the bottom
@export var FLEE_SPEED: float = 200.0        # retreat (survive-the-waves exit)
@export var ROTATE_SLIDE_DUR: float = 1.8    # the rotate-slide swing (bigger = heavier / slower)
@export var ROTATE_TO_DOWN_DUR: float = 1.1  # pivot-in-place back to nose-down at the end of a blockade
@export var BEAM_HOLD: float = 3.0           # hold in the centre lane while the main laser fires down it
@export var BLOCKADE_HOLD: float = 3.5       # hold horizontal while turrets + side lasers rake down
@export var HAZARD_MIN_GAP: float = 8.0      # stage-hazard cadence MIN (wave 3+)
@export var HAZARD_MAX_GAP: float = 14.0     # stage-hazard cadence MAX
@export var HAZARD_SWEEP_SPEED: float = 40.0 # how fast the sweep beam pans edge→centre

const UNDER_LAYER_Z := -2        # draws behind gameplay (player/trail/bullets) but in front of the parallax CanvasLayers
const BG_TINT := Color(0.5, 0.58, 0.72, 1.0)
const BG_SCALE := 0.6            # shrink into the distance when receding into the background

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
	_build_turrets()
	_collect_lasers()
	_fix_firecore_sorting()
	# NOTE: no auto-idle here — start(pos) just places the boss (main.gd passes an off-screen pos for
	# production; the Enemy Bench passes an on-screen pos so its parts are visible/tunable). The off-screen
	# IDLE park (_go_idle) is a BETWEEN-maneuvers concept, driven by play_wave_maneuver / the hazards.


# Pin the visible HULL layers to the under-layer z ABSOLUTELY (z_as_relative=false), so PLAYER SHOTS
# (authored at z=-1, "under the player sprite") and the player's z=-1 engine trail ALWAYS draw OVER the
# battleship's body — without relying on z_index inheriting down from the root. The parts/firecores still
# inherit the root's UNDER_LAYER_Z; only the always-present body sprites are pinned. Beams keep their own z.
func _pin_body_under_layer() -> void:
	for body_name in ["Hull", "GlowMask"]:
		var s := get_node_or_null(body_name) as CanvasItem
		if s != null:
			s.z_as_relative = false
			s.z_index = UNDER_LAYER_Z


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
	"hazard_lane_laser", "hazard_sweep"]


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
	var vp: Vector2 = get_viewport_rect().size
	_exit_background()
	_face_travel(Vector2.DOWN)
	await _travel(position, Vector2(position.x, vp.y + 320.0), FLEE_SPEED)
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


func _maneuver_ok() -> bool:
	return is_instance_valid(self) and not _dying


# ---- Maneuvers ----------------------------------------------------------

# bg edge lane up from behind → high hold → rotate-slide into centre facing DOWN → fan firecores UP into
# the play area while diving out the bottom.
func _m_lane_hook_firecores() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var ex: float = _edge_lane_x(_rand_side())
	_firing_enabled = false
	_enter_background()
	_face_travel(Vector2.UP)
	position = Vector2(ex, vp.y + 240.0)
	await _travel(position, Vector2(ex, HIGH_HOLD_Y), HOOK_RISE_SPEED)
	if not _maneuver_ok(): return
	# STAYS in the background (Roman 2026-07-01): no rise-to-foreground. The boss remains faint/small; the
	# firecores start 0.5x and GROW to 1x as they rise into the foreground toward the player.
	await _rotate_slide(_pivot_local(), Vector2(_center_x(), HIGH_HOLD_Y), PI, ROTATE_SLIDE_DUR)
	if not _maneuver_ok(): return
	_release_firecores(Vector2.DOWN, 0.5)   # emerge small from the distant boss, grow as they rise in
	await _travel(position, Vector2(position.x, vp.y + 260.0), HOOK_DIVE_SPEED, Tween.EASE_IN)  # accelerate out


# As the firecore hook, but the main laser charges during the rotate-slide and fires down the centre lane
# on arrival, then the boss dives out (forcing the player left/right of the beam).
func _m_lane_hook_laser() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var ex: float = _edge_lane_x(_rand_side())
	_firing_enabled = false
	_enter_background()
	_face_travel(Vector2.UP)
	position = Vector2(ex, vp.y + 240.0)
	await _travel(position, Vector2(ex, HIGH_HOLD_Y), HOOK_RISE_SPEED)
	if not _maneuver_ok(): return
	_set_main_laser(true)   # begin the charge (glow fades in during the rise + slide)
	_rise_into_foreground(ROTATE_SLIDE_DUR)   # smooth reverse-dive rise (parallel with the rotate-slide)
	await _rotate_slide(_pivot_local(), Vector2(_center_x(), HIGH_HOLD_Y), PI, ROTATE_SLIDE_DUR)
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	# On arrival (facing down, centre lane) the beam fires down the lane — hold while it fires.
	await get_tree().create_timer(BEAM_HOLD).timeout
	_set_main_laser(false)
	if not _maneuver_ok(): return
	_dive_into_background(ROTATE_SLIDE_DUR)   # smooth recede back into the background
	await _travel(position, Vector2(position.x, vp.y + 260.0), HOOK_DIVE_SPEED, Tween.EASE_IN)


# bg edge lane up from behind → high hold → rotate-slide up HORIZONTAL at centre high hold with the
# fuller side facing down; turrets + that side's lasers rake down; then pivot to nose-down, drop into the
# background and dive out.
func _m_lane_hook_blockade() -> void:
	var side: int = _blockade_side()
	if side < 0:
		await _m_lane_hook_firecores()   # nothing left to blockade with → fall back to a firecore hook
		return
	var vp: Vector2 = get_viewport_rect().size
	var ex: float = _edge_lane_x(_rand_side())
	_firing_enabled = false
	_enter_background()
	_face_travel(Vector2.UP)
	position = Vector2(ex, vp.y + 240.0)
	await _travel(position, Vector2(ex, HIGH_HOLD_Y), HOOK_RISE_SPEED)
	if not _maneuver_ok(): return
	var rot_horizontal: float = (-PI * 0.5) if side == 0 else (PI * 0.5)   # chosen side faces DOWN
	# Land the boss's CENTRE (not the muzzle) on the centre lane at the high hold (Roman 2026-07-01), and
	# rise into the foreground smoothly (parallel) as it swings horizontal.
	_rise_into_foreground(ROTATE_SLIDE_DUR)
	var center_target: Vector2 = _center_pivot_target(Vector2(_center_x(), HIGH_HOLD_Y), rot_horizontal, display_scale)
	await _rotate_slide(_pivot_local(), center_target, rot_horizontal, ROTATE_SLIDE_DUR)
	if not _maneuver_ok(): return
	# Rake: turrets fire + the down-facing side's lasers fire down the play area.
	_firing_enabled = true
	_activate_blockade_lasers(side)
	await get_tree().create_timer(BLOCKADE_HOLD).timeout
	_firing_enabled = false
	_set_side_lasers(false)
	if not _maneuver_ok(): return
	# Pivot in place (around the muzzle) back to nose-down, then recede into the background + dive out.
	await _rotate_slide(_pivot_local(), to_global(_pivot_local()), PI, ROTATE_TO_DOWN_DUR)
	if not _maneuver_ok(): return
	_dive_into_background(0.8)
	await _travel(position, Vector2(position.x, vp.y + 260.0), HOOK_DIVE_SPEED, Tween.EASE_IN)


# fg edge lane from the top → ~1/3 down → sidestep across to centre (drop firecores) → to the opposite
# lane → down + exit. Faces DOWN throughout (a lateral sidestep, not a turn).
func _m_lane_firecore_slide() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var ox: float = _edge_lane_x(1 - side)
	var third_y: float = vp.y / 3.0
	_firing_enabled = false
	_exit_background()
	_face_travel(Vector2.DOWN)
	position = Vector2(ex, -240.0)
	await _travel(position, Vector2(ex, third_y), SLIDE_ENTER_SPEED)
	if not _maneuver_ok(): return
	await _travel(position, Vector2(_center_x(), third_y), SLIDE_CROSS_SPEED)
	if not _maneuver_ok(): return
	_release_firecores(Vector2.DOWN)   # drop them in the centre lane
	await _travel(position, Vector2(ox, third_y), SLIDE_CROSS_SPEED)
	if not _maneuver_ok(): return
	await _travel(position, Vector2(ox, vp.y + 260.0), SLIDE_EXIT_SPEED, Tween.EASE_IN)


# fg edge lane from the top → ~1/3 down charging → fire down its lane → sidestep across (the downward
# beam sweeps with it), cut at centre → to the opposite lane → down + exit.
func _m_lane_laser_slide() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var ox: float = _edge_lane_x(1 - side)
	var third_y: float = vp.y / 3.0
	_firing_enabled = false
	_exit_background()
	_face_travel(Vector2.DOWN)
	position = Vector2(ex, -240.0)
	_set_main_laser(true)   # charge during the descent
	await _travel(position, Vector2(ex, third_y), SLIDE_ENTER_SPEED)
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	# Sweep the firing beam from the edge lane to centre, then cut it.
	await _travel(position, Vector2(_center_x(), third_y), SLIDE_CROSS_SPEED)
	_set_main_laser(false)
	if not _maneuver_ok(): return
	await _travel(position, Vector2(ox, third_y), SLIDE_CROSS_SPEED)
	if not _maneuver_ok(): return
	await _travel(position, Vector2(ox, vp.y + 260.0), SLIDE_EXIT_SPEED, Tween.EASE_IN)


# ---- Stage hazards (wave 3+, boss off-screen) ---------------------------

# Periodic off-screen lane lasers while hazards are armed and the boss isn't mid-maneuver. Needs the main
# laser alive (main-laser maneuvers/hazards are impossible once it's destroyed).
func _hazard_loop() -> void:
	while is_instance_valid(self) and not _dying:
		await get_tree().create_timer(randf_range(HAZARD_MIN_GAP, HAZARD_MAX_GAP)).timeout
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
	_exit_background()
	_face_travel(Vector2.DOWN)
	position = Vector2(lx, -HAZARD_MUZZLE_Y)
	_set_main_laser(true)
	var dur: float = _main_laser_duration()
	if dur > 0.0:
		await get_tree().create_timer(dur).timeout
	_set_main_laser(false)
	if is_instance_valid(self) and not _dying:
		_go_idle()


# As the lane laser, but after the warning + fire it PANS the beam from an edge lane toward the centre
# (translating the off-screen boss so the downward beam sweeps across lanes).
func _hazard_lane_laser_sweep() -> void:
	var side: int = _rand_side()
	var ex: float = _edge_lane_x(side)
	var cx: float = _center_x()
	_exit_background()
	_face_travel(Vector2.DOWN)
	position = Vector2(ex, -HAZARD_MUZZLE_Y)
	_set_main_laser(true)
	await get_tree().create_timer(_main_laser_windup()).timeout   # hold the red warning at the edge lane
	if not _maneuver_ok():
		_set_main_laser(false)
		return
	await _travel(position, Vector2(cx, -HAZARD_MUZZLE_Y), HAZARD_SWEEP_SPEED)   # pan edge→centre while firing
	_set_main_laser(false)
	if is_instance_valid(self) and not _dying:
		_go_idle()


# ---- Movement / presentation helpers -----------------------------------

# Face `dir` of travel. The hull art faces UP (nose = local -Y), so rotate the nose along dir.
# (UP → 0, DOWN → PI, RIGHT → PI/2, LEFT → -PI/2.) Turrets aim independently; lasers use LOCAL_FORWARD
# aim (from their markers) so they follow this rotation automatically.
func _face_travel(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		rotation = dir.angle() + PI * 0.5


# Awaitable move (scripted — the base skips its clamp/pattern while _scripted_move is set). The default
# ease is a WEIGHTY ease-in-out (TRANS_CUBIC) so the huge ship heaves off, slides, and trundles into
# position rather than snapping (Roman 2026-07-01). `speed` sets the AVERAGE speed (the eased curve peaks
# faster mid-move). Exits pass EASE_IN so the ship accelerates away off-screen.
func _travel(from: Vector2, to: Vector2, speed: float, ease_mode: int = Tween.EASE_IN_OUT, trans: int = Tween.TRANS_CUBIC) -> void:
	_scripted_move = true
	position = from
	var dur: float = from.distance_to(to) / maxf(speed, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "position", to, dur).set_trans(trans).set_ease(ease_mode)
	await tw.finished


# Rotate-slide pivoting around the LASER MUZZLE (Roman: "so it appears the rear/side thrusters do the
# work"): tween a pivot point from its current world position to `pivot_to_world` while lerping rotation
# to `rot_to`, holding the muzzle (pivot_local, in the boss's local frame) pinned to that path. Pass the
# current muzzle world position as pivot_to_world for a pivot-IN-PLACE (pure rotation).
func _rotate_slide(pivot_local: Vector2, pivot_to_world: Vector2, rot_to: float, dur: float) -> void:
	_scripted_move = true
	var pivot_from_world: Vector2 = to_global(pivot_local)
	var rot_from: float = rotation
	var tw := create_tween()
	# Read scale.x LIVE inside the lambda (not captured) so the muzzle stays pinned even while a parallel
	# _rise_into_foreground grows the ship. Weighty ease so the body swings around the muzzle with heft.
	tw.tween_method(func(f: float) -> void:
		var pw: Vector2 = pivot_from_world.lerp(pivot_to_world, f)
		var r: float = lerp_angle(rot_from, rot_to, f)
		rotation = r
		global_position = pw - pivot_local.rotated(r) * scale.x
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


# Park off-screen below (background, non-hittable, not firing) — the resting state between attacks.
func _go_idle() -> void:
	_firing_enabled = false
	_set_side_lasers(false)
	_set_main_laser(false)
	_enter_background()
	var vp: Vector2 = get_viewport_rect().size
	_scripted_move = true
	_face_travel(Vector2.UP)
	position = Vector2(Playfield.CENTER.x, vp.y + 260.0)


# The main-laser muzzle in the boss's LOCAL (unrotated) frame — the rotate-slide pivot. Derived from the
# MainLaser instance + its BeamMuzzle marker; falls back to the hull's authored MainLaser marker offset.
func _pivot_local() -> Vector2:
	if _main_laser != null and is_instance_valid(_main_laser):
		var mm := (_main_laser as Node2D).get_node_or_null("BeamMuzzle")
		if mm is Node2D:
			return (_main_laser as Node2D).position + (mm as Node2D).position
		return (_main_laser as Node2D).position
	return Vector2(0, -57)


func _edge_lane_x(side: int) -> float:
	return Lanes.lane_center(0 if side == 0 else Lanes.COUNT - 1)


func _center_x() -> float:
	return Lanes.lane_center(int(Lanes.COUNT / 2))


# "Background" phases DESATURATE + shrink the boss + make its parts non-hittable; "foreground" phases
# restore full colour, scale + hittability. Shading covers the turret barrels + laser hulls too (nested
# part sprites), not just the direct-child hull layers.
func _enter_background() -> void:
	for s in _all_shaded_sprites():
		(s as CanvasItem).modulate = BG_TINT
	scale = Vector2(display_scale, display_scale) * BG_SCALE
	_set_parts_hittable(false)


func _exit_background() -> void:
	for s in _all_shaded_sprites():
		(s as CanvasItem).modulate = Color.WHITE
	scale = Vector2(display_scale, display_scale)
	_set_parts_hittable(true)


# Smoothly recede into the background over `dur`: tween the desaturation (hull + parts) + shrink. Parts go
# non-hittable immediately.
func _dive_into_background(dur: float = 1.0) -> void:
	_set_parts_hittable(false)
	for s in _all_shaded_sprites():
		var ci := s as CanvasItem
		var tw := ci.create_tween()
		tw.tween_property(ci, "modulate", BG_TINT, dur).set_trans(Tween.TRANS_SINE)
	var tw2 := create_tween()
	tw2.tween_property(self, "scale", Vector2(display_scale, display_scale) * BG_SCALE, dur).set_trans(Tween.TRANS_SINE)


# The REVERSE of _dive_into_background (Roman 2026-07-01): smoothly resaturate (hull + parts) + grow back
# to full size over `dur`, as the ship rises OUT of the background into the foreground. Parts become
# hittable immediately (it's committing to the play space). Fire-and-forget (tweens) so it runs in
# PARALLEL with a rotate-slide — _rotate_slide reads scale.x live, so the pivot stays pinned as it grows.
func _rise_into_foreground(dur: float = 1.0) -> void:
	_set_parts_hittable(true)
	for s in _all_shaded_sprites():
		var ci := s as CanvasItem
		var tw := ci.create_tween()
		tw.tween_property(ci, "modulate", Color.WHITE, dur).set_trans(Tween.TRANS_SINE)
	var tw2 := create_tween()
	tw2.tween_property(self, "scale", Vector2(display_scale, display_scale), dur).set_trans(Tween.TRANS_SINE)


# The rotate-slide pins the MUZZLE (pivot_local). To instead land the boss's CENTRE (origin) at
# `center_world` at rotation `rot` and scale `scl`, offset the muzzle target by the rotated muzzle vector.
func _center_pivot_target(center_world: Vector2, rot: float, scl: float) -> Vector2:
	return center_world + _pivot_local().rotated(rot) * scl


# Every sprite that should pick up the background shading: the direct-child hull layers PLUS each live
# part's sprite (a turret barrel nested under its EnemyTurret; a laser's Hull).
func _all_shaded_sprites() -> Array:
	var out: Array = _hull_layers()
	for p in live_parts():
		if is_instance_valid(p):
			var spr := _part_sprite(p)
			if spr != null:
				out.append(spr)
	return out


func _part_sprite(n: Node) -> Sprite2D:
	for c in n.get_children():
		if c is Sprite2D:
			return c as Sprite2D
		var found := _part_sprite(c)
		if found != null:
			return found
	return null


# The hull's direct-child Sprite2D layers (Hull + GlowMask) — discovered by type so it survives renames.
func _hull_layers() -> Array:
	return find_children("*", "Sprite2D", false, false)


func _set_parts_hittable(on: bool) -> void:
	for p in live_parts():
		p.set_deferred("monitorable", on)


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
func _release_firecores(base_dir: Vector2 = Vector2.DOWN, grow_from: float = 1.0) -> void:
	var world: Node = _world()
	if FirecoreHazard == null or world == null:
		return
	var cores: Array = find_children("FireCore*", "", true, false)
	var n: int = cores.size()
	for i in n:
		var core = cores[i]
		if not (core is Node2D):
			continue
		var fc = FirecoreHazard.instantiate()
		world.add_child(fc)
		if fc is CanvasItem:
			(fc as CanvasItem).z_index = UNDER_LAYER_Z   # mid-depth, behind the player (matches the ship)
		var pos: Vector2 = (core as Node2D).global_position
		(fc as Node2D).global_position = pos
		var t: float = 0.0 if n <= 1 else (float(i) / float(n - 1)) * 2.0 - 1.0   # -1..1
		var dir: Vector2 = base_dir.rotated(deg_to_rad(t * FIRECORE_FAN_HALF_DEG))
		if "burst_velocity" in fc:
			fc.burst_velocity = dir * FIRECORE_BURST_SPEED
		if "spawn_scale" in fc:
			fc.spawn_scale = grow_from
		if fc.has_method("start"):
			fc.start(pos)
		(core as CanvasItem).visible = false


# ---- Per-frame: turret gate ---------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_update_turret_gate()


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
	_exit_background()
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
