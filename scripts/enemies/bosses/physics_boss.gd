extends "res://scripts/enemies/bosses/boss_base.gd"

# PHYSICS BOSS — a shared THRUST-DRIVEN rigid-body locomotion base for the game's big "flying-fortress"
# bosses (the Zealot Battleship, the Corporate Director). Extracted from boss_z_battleship.gd on 2026-07-06
# so both bosses share ONE movement system (Roman: "use the same locomotion + thrusters as the battleship").
#
# The ship has MOMENTUM: MAIN thrust pushes FORWARD ONLY (no reverse) along the nose; lateral STRAFE thrust
# (side jets) lets it slide sideways instead of turning to drive; RCS torque swings it about its centre of
# mass; inner "top" thrusters dive it into the background (spring-restored to the fore). Station-keeping
# trim (LIN/ANG_DAMP) bleeds momentum so it always eases to a controllable stop. The hull art faces UP
# (nose = local -Y), so `rotation = dir.angle() + PI/2` points the nose along travel.
#
# Subclasses supply their thruster geometry via _thruster_defs(), their pinned hull-layer names via
# _pinned_body_names(), and stop their weapons via _stop_firing() (called on idle). Everything else — the
# integrator, the awaitable pilot primitives (_fly_to/_face/_fly_through/_settle/_dive/_teleport/_go_idle),
# the depth→scale/shading/hittability, the visible thruster flares, and knockback() — lives here. The
# @export knobs are live-tunable in each boss's Lab (tune → Copy GDScript → paste the block back).

const EngineFlareC = preload("res://scripts/effects/engine_flare.gd")

# MOVEMENT — the physics-inspired thrust model. @export so each boss's Lab live-tunes the heft.
@export var MAIN_ACCEL: float = 380.0        # forward thrust (px/s²) along the nose
@export var STRAFE_ACCEL: float = 360.0      # LATERAL thrust (side thrusters) — it PREFERS to strafe, not turn
@export var MAX_SPEED: float = 200.0         # linear speed cap (keep < the 480 px/s clarity ceiling)
@export var LIN_DAMP: float = 3.0            # station-keeping drag (proportional, 1/s) → always eases to a stop
@export var RCS_ANG_ACCEL: float = 10.0      # yaw torque (rad/s²) — brisk enough that the flip OVERLAPS the
@export var MAX_ANG_SPEED: float = 3.4       # slide (no spinning in place after arriving)
@export var ANG_DAMP: float = 3.2            # yaw drag (proportional, 1/s) → terminal ~3.1 rad/s (180° in ~1s)
@export var DEPTH_ACCEL: float = 5.0         # top-thruster dive accel (1/s²)
@export var DEPTH_SPRING: float = 6.0        # restoring pull back to the foreground
@export var DEPTH_DAMP: float = 4.0
@export var ARRIVE_RADIUS: float = 52.0      # cut thrust + orient to the final heading within this of the target
@export var FACE_GAIN: float = 6.0           # yaw controller P gain
@export var FACE_DAMP: float = 2.0           # yaw controller D gain (higher = less overshoot at the faster yaw)

# Fly-to release: proximity only (position + heading) — it carries momentum into the next leg for a
# continuous, no-dead-air flow. Bounded by FLY_TIMEOUT so a maneuver can never hang the wave gate.
const ARRIVE_TOL := 20.0
const FACE_TOL := 0.16
const FLY_TIMEOUT := 8.0

const UNDER_LAYER_Z := -2        # draws behind gameplay (player/trail/bullets) but in front of the parallax CanvasLayers
const BG_TINT := Color(0.5, 0.58, 0.72, 1.0)
const BG_SCALE := 0.6            # shrink into the distance when receding into the background

# --- thrust-driven rigid-body state (see the MOVEMENT knobs above) ---
enum { M_IDLE, M_FLY, M_THROUGH, M_FACE }   # pilot target modes
var _vel: Vector2 = Vector2.ZERO   # world linear velocity (px/s)
var _ang_vel: float = 0.0          # angular velocity (rad/s)
var _depth: float = 0.0            # 0 = foreground, 1 = deep background
var _depth_vel: float = 0.0
var _last_hittable: bool = true    # parts-hittable state (retoggled when depth crosses 0.5)
var _tgt_mode: int = M_IDLE
var _tgt_pos: Vector2 = Vector2.ZERO
var _tgt_heading: float = 0.0
var _tgt_depth: float = 0.0
var _fly_dir: Vector2 = Vector2.DOWN
var _cmd_throttle: float = 0.0     # last-frame thruster commands (drive the flares)
var _cmd_strafe: float = 0.0       # lateral thrust command (+ = local +x / right)
var _cmd_yaw: float = 0.0
var _cmd_dive: float = 0.0
var _flares: Dictionary = {}       # group name → Array[EngineFlare]


# ---- Overridable hooks (subclasses specialize; base defaults are inert) ------------------------------

# Thruster layout: [group_name, local_pos, plume_rotation] rows (see the battleship for the format). The
# base has none — a boss with no defs simply shows no flares.
func _thruster_defs() -> Array:
	return []


# Stop all of this boss's weapons — called by _go_idle when it parks off-screen. Default no-op.
func _stop_firing() -> void:
	pass


# The names of the always-present hull Sprite2D layers to pin absolutely at the under-layer z (so player
# shots always draw over the body). Override per-boss (the layer nodes are named differently).
func _pinned_body_names() -> Array:
	return ["Hull", "GlowMask"]


# ---- Per-frame integrate (subclasses call super._process, then add their own gates) ------------------

func _process(delta: float) -> void:
	super._process(delta)
	_integrate_physics(delta)


# Add an impulse to the linear velocity — an external shove (e.g. a shot knock-away). The integrator caps
# the result at MAX_SPEED and the station-keeping drag bleeds it back off, so the ship recovers to its pose.
func knockback(impulse: Vector2) -> void:
	_vel += impulse


# ---- Thrust-driven rigid-body movement (physics-inspired) --------------------------------------------

# Integrate the rigid body each frame: the pilot picks throttle/yaw/dive from the target pose, then the
# body accumulates linear velocity (forward-only main thrust + station-keeping drag), angular velocity
# (RCS torque about the CoM), and depth (top thrusters vs a foreground-restoring spring). Runs in
# _process so it pauses with the tree.
func _integrate_physics(delta: float) -> void:
	if not is_instance_valid(self):
		return
	delta = minf(delta, 1.0 / 30.0)
	_pilot_step(delta)
	# Linear — main thrust FORWARD along the nose (no reverse) + LATERAL strafe thrust (side jets), then
	# proportional drag (station-keeping trim) so it always eases to a controllable stop.
	_vel += _nose_dir() * (MAIN_ACCEL * _cmd_throttle) * delta
	_vel += _nose_perp() * (STRAFE_ACCEL * _cmd_strafe) * delta
	_vel -= _vel * (LIN_DAMP * delta)
	var sp: float = _vel.length()
	if sp > MAX_SPEED:
		_vel *= MAX_SPEED / sp
	position += _vel * delta
	# Angular — RCS torque swings the hull about its origin (= centre of mass), then trims to rest.
	_ang_vel += RCS_ANG_ACCEL * _cmd_yaw * delta
	_ang_vel -= _ang_vel * (ANG_DAMP * delta)
	_ang_vel = clampf(_ang_vel, -MAX_ANG_SPEED, MAX_ANG_SPEED)
	rotation += _ang_vel * delta
	# Depth — the top thrusters push it in (dive_cmd) against a spring that restores toward the fore.
	_depth_vel += (DEPTH_ACCEL * _cmd_dive - DEPTH_SPRING * _depth - DEPTH_DAMP * _depth_vel) * delta
	_depth = clampf(_depth + _depth_vel * delta, 0.0, 1.0)
	_apply_depth()
	_update_flares()


# The control law → the frame's throttle / strafe / yaw / dive commands. The ship holds its COMMANDED
# heading and PREFERS TO STRAFE (side jets) to reach a target, only thrusting forward for the ahead
# component — so it slides sideways instead of turning to drive. Main thrust is forward-only (no reverse).
func _pilot_step(_delta: float) -> void:
	_cmd_dive = clampf(_tgt_depth, 0.0, 1.0)
	_cmd_throttle = 0.0
	_cmd_strafe = 0.0
	match _tgt_mode:
		M_IDLE:
			_cmd_yaw = 0.0
		M_FACE:
			_cmd_yaw = _yaw_to(_tgt_heading)
		M_THROUGH:
			_cmd_yaw = _yaw_to(_tgt_heading)
			_cmd_throttle = clampf(_nose_dir().dot(_fly_dir), 0.0, 1.0)
			_cmd_strafe = clampf(_nose_perp().dot(_fly_dir), -1.0, 1.0)
		M_FLY:
			_cmd_yaw = _yaw_to(_tgt_heading)                    # HOLD the commanded heading (don't turn to travel)
			var to_t: Vector2 = _tgt_pos - position
			var dist: float = to_t.length()
			if dist > ARRIVE_TOL:
				var dir: Vector2 = to_t / dist
				var taper: float = clampf(dist / ARRIVE_RADIUS, 0.0, 1.0)   # ease off approaching the target
				_cmd_throttle = clampf(_nose_dir().dot(dir), 0.0, 1.0) * taper    # forward (ahead component)
				_cmd_strafe = clampf(_nose_perp().dot(dir), -1.0, 1.0) * taper    # STRAFE (lateral component)


# PD yaw controller → a torque command in [-1,1]. P pulls toward the heading, D damps the spin.
func _yaw_to(target_heading: float) -> float:
	var err: float = wrapf(target_heading - rotation, -PI, PI)
	return clampf(err * FACE_GAIN - _ang_vel * FACE_DAMP, -1.0, 1.0)


# The world direction the nose points (hull art faces UP = local -Y).
func _nose_dir() -> Vector2:
	return Vector2.UP.rotated(rotation)


# The world lateral (strafe) axis = the nose rotated +90° (= local +x). +_cmd_strafe pushes this way.
func _nose_perp() -> Vector2:
	return _nose_dir().rotated(PI * 0.5)


# The rotation that points the nose along `dir` (UP→0, DOWN→PI, RIGHT→PI/2, LEFT→-PI/2).
func _heading_for(dir: Vector2) -> float:
	return (dir.angle() + PI * 0.5) if dir.length_squared() > 0.0001 else rotation


# Map _depth (0 fg … 1 bg) → scale + desaturation + parts-hittable. The tint covers nested part sprites
# too. Only re-toggles hittability when it crosses the 0.5 threshold.
func _apply_depth() -> void:
	scale = Vector2(display_scale, display_scale) * lerp(1.0, BG_SCALE, _depth)
	var tint: Color = Color.WHITE.lerp(BG_TINT, _depth)
	for spr in _all_shaded_sprites():
		(spr as CanvasItem).modulate = tint
	var want_hit: bool = _depth < 0.5
	if want_hit != _last_hittable:
		_last_hittable = want_hit
		_set_parts_hittable(want_hit)


# --- Awaitable pilot primitives ---

# Fly to a pose: cruise to `pos`, orient to `heading`, settle. `depth`>=0 sets the depth target. Bounded
# by FLY_TIMEOUT so a maneuver can never hang the wave gate (it releases NEAR the pose if it can't settle).
func _fly_to(pos: Vector2, heading: float, depth: float = -1.0) -> void:
	_tgt_pos = pos
	_tgt_heading = heading
	if depth >= 0.0:
		_tgt_depth = depth
	_tgt_mode = M_FLY
	var t: float = 0.0
	while _maneuver_ok() and t < FLY_TIMEOUT:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		if position.distance_to(_tgt_pos) < ARRIVE_TOL \
				and absf(wrapf(_tgt_heading - rotation, -PI, PI)) < FACE_TOL:
			return   # release on proximity — carry momentum into the next leg (no dead air)


# Coast to a near-stop (used before releasing a payload / firing so it happens once the movement is DONE,
# not mid-drift). Keeps the current target so drag settles it in place; bounded by max_wait.
func _settle(max_wait: float = 1.2) -> void:
	var t: float = 0.0
	while _maneuver_ok() and t < max_wait:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		if _vel.length() < 12.0 and absf(_ang_vel) < 0.3:
			return


# Thrust along `dir` (holding `heading`) until the hull is FULLY off-screen (or max_time elapses). Use for
# maneuver EXITS: a fixed-duration _fly_through can leave a tall hull half on-screen when _go_idle then
# teleports it to the park — reading as the boss "vanishing" mid-air (Roman 2026-07-06). This flies it
# clean off first, so the idle teleport is invisible.
func _fly_off(dir: Vector2, heading: float, depth: float, max_time: float = 4.5) -> void:
	_fly_dir = dir.normalized()
	_tgt_heading = heading
	_tgt_depth = depth
	_tgt_mode = M_THROUGH
	var vp: Vector2 = get_viewport_rect().size
	var margin: float = 110.0   # > half a mega-hull, so the whole ship clears the edge before the idle teleport
	var t: float = 0.0
	while _maneuver_ok() and t < max_time:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		var p: Vector2 = position
		if p.y > vp.y + margin or p.y < -margin or p.x < -margin or p.x > vp.x + margin:
			return


# Thrust along a world direction (holding `heading`) for `dur` seconds — passes + exits (no arrival brake).
func _fly_through(dir: Vector2, heading: float, depth: float, dur: float) -> void:
	_fly_dir = dir.normalized()
	_tgt_heading = heading
	_tgt_depth = depth
	_tgt_mode = M_THROUGH
	var t: float = 0.0
	while _maneuver_ok() and t < dur:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()


# Yaw-in-place to a heading (the hull swings about its CoM).
func _face(heading: float) -> void:
	_tgt_heading = heading
	_tgt_mode = M_FACE
	var t: float = 0.0
	while _maneuver_ok() and t < FLY_TIMEOUT:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()
		if absf(wrapf(heading - rotation, -PI, PI)) < FACE_TOL and absf(_ang_vel) < 0.4:
			return


# Set the depth target (fire-and-forget; the physics eases there). 0 = foreground, 1 = deep background.
func _dive(target_depth: float) -> void:
	_tgt_depth = clampf(target_depth, 0.0, 1.0)


# Snap the pose (off-screen placement at a maneuver's start / idle park — the player never sees the jump).
func _teleport(pos: Vector2, heading: float, depth: float) -> void:
	position = pos
	rotation = heading
	_vel = Vector2.ZERO
	_ang_vel = 0.0
	_depth = clampf(depth, 0.0, 1.0)
	_depth_vel = 0.0
	_tgt_pos = pos
	_tgt_heading = heading
	_tgt_depth = _depth
	_tgt_mode = M_IDLE
	_apply_depth()


# Park off-screen below (deep background, non-hittable, not firing) — the resting state between attacks.
func _go_idle() -> void:
	_stop_firing()
	var vp: Vector2 = get_viewport_rect().size
	_teleport(Vector2(Playfield.CENTER.x, vp.y + 260.0), _heading_for(Vector2.UP), 1.0)


# True while a maneuver may keep running (the boss is alive + not dying). The awaitable primitives poll it.
func _maneuver_ok() -> bool:
	return is_instance_valid(self) and not _dying


func _edge_lane_x(side: int) -> float:
	return Lanes.lane_center(0 if side == 0 else Lanes.COUNT - 1)


func _center_x() -> float:
	return Lanes.lane_center(int(Lanes.COUNT / 2))


# --- Thruster flares (visible thrust; reuse EngineFlare) ---

func _build_thruster_flares() -> void:
	for d in _thruster_defs():
		var g: String = String(d[0])
		var fl: Sprite2D = EngineFlareC.new()
		fl.position = d[1]
		fl.rotation = float(d[2])
		fl.visible = false
		fl.z_as_relative = false
		fl.z_index = UNDER_LAYER_Z + 1   # OVER the boss body (the hull is pinned at UNDER_LAYER_Z)
		add_child(fl)
		if not _flares.has(g):
			_flares[g] = []
		_flares[g].append(fl)


# Light each thruster group by the command driving it: main→forward, spos/sneg→strafe sign, ycw/yccw→yaw
# sign, top→dive. Called each physics frame.
func _update_flares() -> void:
	_set_flare_group("main", _cmd_throttle)
	_set_flare_group("spos", maxf(_cmd_strafe, 0.0))
	_set_flare_group("sneg", maxf(-_cmd_strafe, 0.0))
	_set_flare_group("ycw", maxf(_cmd_yaw, 0.0))
	_set_flare_group("yccw", maxf(-_cmd_yaw, 0.0))
	_set_flare_group("top", _cmd_dive)


func _set_flare_group(g: String, throttle: float) -> void:
	if not _flares.has(g):
		return
	var on: bool = throttle > 0.06 and not _dying
	var s: float = 0.35 + 0.6 * clampf(throttle, 0.0, 1.0)
	for fl in _flares[g]:
		if is_instance_valid(fl):
			fl.visible = on
			if on:
				fl.scale = Vector2(s, s)


# --- Depth shading + hull pin ---

# Every sprite that should pick up the background shading: the direct-child hull layers PLUS each live
# part's sprite (nested part barrels / hulls).
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


# The hull's direct-child Sprite2D layers — discovered by type so it survives renames.
func _hull_layers() -> Array:
	return find_children("*", "Sprite2D", false, false)


func _set_parts_hittable(on: bool) -> void:
	for p in live_parts():
		p.set_deferred("monitorable", on)


# Pin the visible HULL layers to the under-layer z ABSOLUTELY (z_as_relative=false), so PLAYER SHOTS
# (authored at z=-1) + the player's z=-1 engine trail ALWAYS draw OVER the boss body — without relying on
# z_index inheriting down from the root. Parts/decorations still inherit the root's UNDER_LAYER_Z.
func _pin_body_under_layer() -> void:
	for body_name in _pinned_body_names():
		var s := get_node_or_null(body_name) as CanvasItem
		if s != null:
			s.z_as_relative = false
			s.z_index = UNDER_LAYER_Z
