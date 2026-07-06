extends "res://scripts/enemies/movement_pattern.gd"

# Hand-authored flight path (2026-07-06). A movement pattern that follows a polyline / Catmull-Rom
# spline authored in the Path Editor (scripts/dev/path_editor.gd) as a list of waypoints in a
# NORMALIZED authoring space, then baked into scripts/enemies/patterns/authored_path_library.gd.
#
# Authoring space (resolution-independent so a path survives any playfield/lane change):
#   x — LANE units, 0 .. Lanes.COUNT-1 (fractional allowed). Mapped to an absolute viewport X via the
#       lane pitch (lane 3 = playfield centre). In RELATIVE mode x is an OFFSET added to the spawn
#       lane, so one authored path reuses across all 7 lanes (composes with the wave/formation system).
#   y — BAND PROGRESS 0 .. 1 down the playfield (0 = top/spawn edge, 1 = bottom/exit edge). Mapped
#       across [Playfield.Y_MIN, Playfield.Y_MAX].
#
# Motion is CONSTANT SPEED along arc-length (chassis move_speed × speed_scale, snapped to a Clarity
# rung) — no parametric speed wobble. Position is set closed-form from a single arc-length cursor, so
# it is deterministic + lockstep-safe (like lane_path). Facing is NOT applied here — the batch-1
# auto-rotation turn-rate cap (enemy_base._apply_auto_rotation) banks the hull from the velocity.
#
# Mirror: `mirrored` reflects the lateral geometry around lane 3 (COUNT/2). director._apply_direction
# sets it from a wave's direction_override (it duplicates the pattern + sets .mirrored), so the same
# authored path can be flipped L<->R by the conductor. Mirroring is applied AFTER the relative/absolute
# lane resolve, around the board centre.
#
# path_phase_capable(): true ONLY when the authored y is monotonically non-decreasing (computed once
# from the data). A descending path gets path-phase firing for free; a looping / rising path fires on
# the standard cadence.

const Clarity := preload("res://scripts/systems/clarity.gd")

# --- Authored data (set by the library factory / editor before on_start) ---
@export var waypoints: Array = []      # Array of Vector2(x_lane, y_bandprogress) in authoring space
@export var speed_scale: float = 1.0   # multiplies chassis move_speed
@export var relative: bool = false     # x are offsets from the spawn lane (true) or absolute lanes (false)
@export var smoothing: float = 0.0     # 0 = straight polyline; >0 = Catmull-Rom rounding strength (0..1)
@export var mirrored: bool = false     # reflect lateral geometry around lane 3
@export var dwell: Array = []          # optional per-waypoint hold seconds (parallel to waypoints)

# Catmull-Rom subdivision count per authored segment when smoothing > 0. Fixed + deterministic.
const SMOOTH_SUBDIV := 8
# Band inset for the X clamp — half a lane width so a clamped hull sits fully inside the band edge.
const EDGE_INSET := 12.0

# --- Resolved (pixel-space) state, rebuilt in on_start ---
var _pts: PackedVector2Array = PackedVector2Array()   # resolved polyline in pixels (post-smoothing)
var _seg_len: PackedFloat32Array = PackedFloat32Array() # length of each segment
var _cum_len: PackedFloat32Array = PackedFloat32Array() # cumulative arc-length at each point
var _total_len: float = 0.0
var _anchor_x: float = 0.0             # spawn lane center X (relative mode origin)
var _dist: float = 0.0                 # arc-length cursor
var _dwell_at: PackedFloat32Array = PackedFloat32Array() # dwell seconds keyed by resolved point index
var _dwell_t: float = 0.0              # remaining dwell at the current point
var _dwell_idx: int = -1               # last point index whose dwell was consumed
var _exit_dir: Vector2 = Vector2(0.0, 1.0)  # unit direction of the final segment (continue-off)
var _monotone_y: bool = true           # cached from data


# --- Authoring-space -> pixel mapping (static so the editor can dogfood identical math) ---
static func lane_to_x(lane_units: float) -> float:
	return Lanes.FIRST_CENTER + Lanes.PITCH * lane_units


static func bandprogress_to_y(p: float) -> float:
	return Playfield.Y_MIN + clampf(p, 0.0, 1.0) * (Playfield.Y_MAX - Playfield.Y_MIN)


# Resolve one authored waypoint to a pixel position given the anchor X (relative mode) + mirror.
static func resolve_point(wp: Vector2, anchor_x: float, is_relative: bool, is_mirrored: bool) -> Vector2:
	var x: float
	if is_relative:
		# x is a lane OFFSET from the spawn lane; mirror flips the offset sign.
		var off: float = wp.x
		if is_mirrored:
			off = -off
		x = anchor_x + off * Lanes.PITCH
	else:
		# x is an absolute lane coordinate; mirror reflects around lane 3 (COUNT-1)/2.
		var lane_u: float = wp.x
		if is_mirrored:
			lane_u = float(Lanes.COUNT - 1) - lane_u
		x = lane_to_x(lane_u)
	# Clamp X into the playfield band (inset by a lane half-width so the hull stays fully shootable).
	# Lane-relative paths spawned near an edge would otherwise push a large offset off the band; this
	# mirrors lane_path's amplitude clamp — keep it on the board, never leave the 216px band.
	x = clampf(x, Playfield.X_MIN + EDGE_INSET, Playfield.X_MAX - EDGE_INSET)
	return Vector2(x, bandprogress_to_y(wp.y))


# Whether an authored waypoint list descends monotonically (non-decreasing y).
static func is_monotone_y(wps: Array) -> bool:
	var prev: float = -1.0
	for wp in wps:
		var y: float = (wp as Vector2).y if wp is Vector2 else float((wp as Array)[1])
		if y < prev - 0.0001:
			return false
		prev = y
	return true


func on_start(enemy) -> void:
	# Idempotent (re-called after each parallax recycle fly-back).
	_anchor_x = enemy.position.x
	_dist = 0.0
	_dwell_t = 0.0
	_dwell_idx = -1
	_monotone_y = is_monotone_y(waypoints)
	_rebuild_polyline()
	# Snap the enemy onto the first waypoint (spawn teleport — permitted by the contract).
	if _pts.size() > 0:
		enemy.position = _pts[0]
		# Seed the dwell at the first point.
		if _dwell_at.size() > 0 and _dwell_at[0] > 0.0:
			_dwell_t = _dwell_at[0]
			_dwell_idx = 0


func _rebuild_polyline() -> void:
	_pts = PackedVector2Array()
	_dwell_at = PackedFloat32Array()
	if waypoints.size() < 2:
		# Degenerate: a single (or no) waypoint — hold in place then straight down as exit.
		if waypoints.size() == 1:
			_pts.append(resolve_point(_to_v2(waypoints[0]), _anchor_x, relative, mirrored))
			_dwell_at.append(_dwell_for(0))
		_exit_dir = Vector2(0.0, 1.0)
		_recompute_arc()
		return
	# Resolve authored waypoints to pixels.
	var base: PackedVector2Array = PackedVector2Array()
	for wp in waypoints:
		base.append(resolve_point(_to_v2(wp), _anchor_x, relative, mirrored))
	if smoothing <= 0.0:
		_pts = base
		# Dwell maps 1:1 onto authored points.
		for i in base.size():
			_dwell_at.append(_dwell_for(i))
	else:
		# Catmull-Rom: subdivide each authored segment; the authored knots keep their dwell, the
		# in-between subdivision points get 0 dwell. `smoothing` (0..1) blends between a straight
		# polyline (0) and a full Catmull-Rom (1) by lerping subdivided points toward the chord.
		var n: int = base.size()
		for i in range(n - 1):
			var p0: Vector2 = base[maxi(0, i - 1)]
			var p1: Vector2 = base[i]
			var p2: Vector2 = base[i + 1]
			var p3: Vector2 = base[mini(n - 1, i + 2)]
			var steps: int = SMOOTH_SUBDIV if smoothing > 0.0 else 1
			for s in steps:
				var t: float = float(s) / float(steps)
				var spline: Vector2 = _catmull_rom(p0, p1, p2, p3, t)
				var chord: Vector2 = p1.lerp(p2, t)
				var pt: Vector2 = chord.lerp(spline, clampf(smoothing, 0.0, 1.0))
				_pts.append(pt)
				_dwell_at.append(_dwell_for(i) if s == 0 else 0.0)
		_pts.append(base[n - 1])
		_dwell_at.append(_dwell_for(n - 1))
	_recompute_arc()


func _recompute_arc() -> void:
	_seg_len = PackedFloat32Array()
	_cum_len = PackedFloat32Array()
	_total_len = 0.0
	if _pts.size() == 0:
		_exit_dir = Vector2(0.0, 1.0)
		return
	_cum_len.append(0.0)
	for i in range(_pts.size() - 1):
		var d: float = _pts[i].distance_to(_pts[i + 1])
		_seg_len.append(d)
		_total_len += d
		_cum_len.append(_total_len)
	# Exit direction = last non-degenerate segment (continue straight off-screen from the final wp).
	_exit_dir = Vector2(0.0, 1.0)
	for i in range(_pts.size() - 1, 0, -1):
		var v: Vector2 = _pts[i] - _pts[i - 1]
		if v.length() > 0.001:
			_exit_dir = v.normalized()
			break


func compute_step(enemy, delta: float) -> Vector2:
	if _pts.size() == 0:
		return Vector2(0.0, _move_speed(enemy) * speed_scale * delta)
	# Honor a dwell hold at the current knot before advancing.
	if _dwell_t > 0.0:
		_dwell_t = maxf(0.0, _dwell_t - delta)
		return Vector2.ZERO
	var speed: float = _snapped_speed(enemy)
	var step_len: float = speed * delta
	var target: Vector2
	if _dist + step_len < _total_len:
		_dist += step_len
		target = _pos_at(_dist)
		# Trigger dwell if we just passed a knot that has one.
		_maybe_dwell(_dist)
	else:
		# Past the final waypoint: continue straight along the exit direction.
		var overrun: float = (_dist + step_len) - _total_len
		_dist = _total_len + overrun
		if _pts.size() > 0:
			target = _pts[_pts.size() - 1] + _exit_dir * overrun
	return target - enemy.position


# Position at arc-length d along the resolved polyline (clamped to the ends).
func _pos_at(d: float) -> Vector2:
	if _pts.size() == 1:
		return _pts[0]
	if d <= 0.0:
		return _pts[0]
	if d >= _total_len:
		return _pts[_pts.size() - 1]
	# Binary-ish linear scan (paths are short — a handful of segments).
	for i in range(_seg_len.size()):
		var seg_start: float = _cum_len[i]
		var seg_end: float = _cum_len[i + 1]
		if d <= seg_end:
			var seg: float = maxf(_seg_len[i], 0.0001)
			var t: float = (d - seg_start) / seg
			return _pts[i].lerp(_pts[i + 1], t)
	return _pts[_pts.size() - 1]


# If the cursor crossed a knot (point index) that carries a dwell, start holding there once.
func _maybe_dwell(d: float) -> void:
	# Find the knot index at/just-before d.
	for i in range(_dwell_at.size()):
		if _dwell_at[i] <= 0.0 or i <= _dwell_idx:
			continue
		if i >= _cum_len.size():
			break
		if d >= _cum_len[i]:
			_dwell_t = _dwell_at[i]
			_dwell_idx = i
			break


# Centripetal-free uniform Catmull-Rom interpolation between p1 and p2 (p0/p3 are the neighbors).
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _snapped_speed(enemy) -> float:
	return Clarity.snap_to_rung(_move_speed(enemy) * maxf(0.01, speed_scale))


func _dwell_for(i: int) -> float:
	return float(dwell[i]) if i < dwell.size() else 0.0


func _to_v2(wp) -> Vector2:
	if wp is Vector2:
		return wp
	if wp is Array and (wp as Array).size() >= 2:
		return Vector2(float(wp[0]), float(wp[1]))
	return Vector2.ZERO


func path_phase_capable() -> bool:
	# Only monotone-y descenders get path-phase firing; looping/rising paths use the cadence timer.
	return is_monotone_y(waypoints)


func fidelity() -> int:
	# EXACT — the authored geometry is closed-form + mirror-sacred; the facing turn-rate cap handles
	# banking. (Bypasses the velocity filter, like lane_path's non-STEP shapes.)
	return ShipKinematics.Fidelity.EXACT
