extends "res://scripts/enemies/movement_pattern.gd"

# Lane-relative movement: descend while optionally shifting between vertical
# lanes (Lanes geometry, scripts/lanes.gd). Deterministic + mirrorable so the
# lane conductor can anchor + reflect ONE authored path across the board.
#
# The conductor places the enemy on a lane center (sets position.x at spawn);
# on_start captures that as the anchor (boss_sweep.gd precedent). All lateral
# motion is expressed relative to that anchor in LANE units (* Lanes.PITCH),
# never absolute lanes — so the same path reads identically from any anchor.
#
# Closed-form shapes (keyframe format deferred — plan §6):
#   STRAIGHT  — hold the spawn lane, pure descent.
#   WEAVE     — sinusoidal swing of +/- weave_lanes around the spawn lane.
#   HOOK      — one-way smoothstep from the spawn lane to spawn + shift_lanes,
#               beginning after shift_delay, over shift_duration, then holds the
#               destination lane while descending. (hold-then-go = shift_delay>0.)
#
# Mirror (s_curve.gd precedent): `mirrored` flips lateral direction L<->R. With
# enemy auto_rotate on, banking follows the velocity for free — no flip_h needed
# (lane spec §1.4). The conductor chooses mirror to fit the board + pursue/avoid.
#
# Speed naming: the descent export is `down_speed` (ends in `_speed`) so
# enemy_core._apply_sector_speed_scale sector-scales AND clarity-clamps it to the
# 8 px/f ceiling (enemy_core.gd:108/117). Author the base on a rung (mult of 60).

#   STEP      — hold a lane, hop step_lanes to a new lane, hold, repeat. Knobs:
#               hold_time, step_time, step_lanes (1 = adjacent), step_repeat (keep
#               hopping vs one hop), step_pingpong (reverse at edges vs advance).

const LaneTraffic = preload("res://scripts/lane_traffic.gd")

#   DIVE_RETURN — dive down a lane; at the fire-zone midpoint, curve into the adjacent
#               lane (shift_lanes) AND reverse the descent to climb back UP and off the
#               top. For missile/rocket droppers: drop the volley on the way down, then
#               turn and burn off-screen. The "lane_hook" production key. Sets FREE_ANY_EDGE
#               in on_start so the top exit frees the enemy (CYCLE_BOTTOM never watches the top).
#   LANE_CUT  — dive down a lane; at the fire-zone midpoint, curve LEFT/RIGHT and run
#               HORIZONTALLY off the side. The "lane_cut" key. Also FREE_ANY_EDGE.
enum Shape { STRAIGHT, WEAVE, HOOK, STEP, DIVE_RETURN, LANE_CUT }

@export var shape: Shape = Shape.STRAIGHT
@export var down_speed: float = 120.0       # px/s descent (rung 2). Clarity-clamped.
@export var mirrored: bool = false          # reflect lateral direction L<->R

@export_group("Hook")
@export var shift_lanes: int = 0            # signed lane delta for the one-way hook
@export var shift_delay: float = 0.0        # s to hold the spawn lane before hooking
@export var shift_duration: float = 0.8     # s the hook transition takes
# Drifter mode (Roman 2026-06-06): drive the hook off the ENGAGEMENT BAND instead
# of a timer — hold the spawn lane through entry, start sliding as the enemy crosses
# into the fire zone, and be fully in the destination lane by the band's bottom
# (Zones.band_progress 0->1). Yields a slow, fire-zone-spanning drift. The commit
# free-check still applies (and may delay the commit; the slide then spans the
# remaining band so it still lands by the bottom). Shift_delay/duration are ignored.
@export var zone_timed: bool = false

@export_group("Dive-Return")
@export var return_trigger_bp: float = 0.5  # band_progress (0..1) at which the dive turns back up
@export var return_curve_time: float = 0.6  # seconds the lateral curve into the adjacent lane takes

@export_group("Weave")
@export var weave_lanes: float = 1.0        # swing amplitude in lanes (+/-)
@export var weave_frequency: float = 0.8    # swings per second

@export_group("Step")
@export var hold_time: float = 0.8          # s to hold a lane before hopping
@export var step_time: float = 0.25         # s for the lateral hop between lanes
@export var step_lanes: int = 1             # lanes per hop (1 = adjacent)
@export var step_repeat: bool = true        # keep hopping (false = one hop then hold)
@export var step_pingpong: bool = true      # reverse at edges (false = advance + clamp)
# Coordinated row step (P2d): when true the lateral offset is a SHARED, deterministic
# sequence (not a per-lane self-step) so a whole ROW shifts in unison — the gap
# relocates as one. The conductor stamps the same step_offset_lo/hi + step_start_dir
# + timing on every member; identical inputs + a same-frame spawn => identical motion,
# preserving relative spacing (no merges, so the lane free-check is unnecessary). The
# offset is anchor-relative (lanes), oscillating in [lo, hi] which the conductor sizes
# so EVERY member stays on the board.
@export var step_synced: bool = false
@export var step_offset_lo: int = 0
@export var step_offset_hi: int = 0
@export var step_start_dir: int = 1

var _t: float = 0.0
var _anchor_x: float = 0.0
# DIVE_RETURN state: dive until the trigger, then curve to the adjacent lane + climb back up.
var _return_started: bool = false
var _return_t: float = 0.0
var _return_anchor_x: float = 0.0
# HOOK (Shifter) state: the commit is one-way and gated on the target lane being
# clear (P2 lane-awareness). Until committed the enemy holds its spawn lane.
var _hook_committed: bool = false
var _hook_start_t: float = 0.0
var _hook_commit_bp: float = 0.0   # band_progress at commit (zone_timed remap origin)
# Latest band_progress at which a zone-timed Drifter will still start a slide — past
# this there isn't enough band left to land in the new lane gracefully, so it rides
# its lane straight down instead.
const ZONE_COMMIT_MAX: float = 0.7
# STEP state
var _anchor_lane: int = 0
var _cur_lane: int = 0
var _next_lane: int = 0
var _step_dir: int = 1
var _step_phase: int = 0   # 0 = holding, 1 = hopping
var _phase_t: float = 0.0
var _from_x: float = 0.0
var _to_x: float = 0.0
var _stepped_once: bool = false


func on_start(enemy) -> void:
	# Idempotent (re-called after each parallax recycle fly-back).
	_t = 0.0
	_anchor_x = enemy.position.x
	# STEP init: hops are relative to the spawn lane; first hop biased toward the
	# side with more room (mirror flips it).
	_anchor_lane = Lanes.nearest_lane(_anchor_x)
	_cur_lane = _anchor_lane
	_next_lane = _anchor_lane
	_step_dir = -1 if _anchor_lane > Lanes.COUNT / 2 else 1
	if mirrored:
		_step_dir = -_step_dir
	_step_phase = 0
	_phase_t = 0.0
	_stepped_once = false
	_hook_committed = false
	_hook_start_t = 0.0
	_hook_commit_bp = 0.0
	_return_started = false
	_return_t = 0.0
	_return_anchor_x = _anchor_x
	# DIVE_RETURN climbs back up off the TOP, LANE_CUT runs off the SIDE — both need
	# FREE_ANY_EDGE so the exit frees the enemy (CYCLE_BOTTOM only watches bottom/side).
	# 1 = OffscreenMode.FREE_ANY_EDGE.
	if shape == Shape.DIVE_RETURN or shape == Shape.LANE_CUT:
		enemy.offscreen_mode = 1


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var sign_x: float = -1.0 if mirrored else 1.0
	var target_x: float = _anchor_x
	match shape:
		Shape.WEAVE:
			var amp: float = _clamp_amp(absf(weave_lanes) * Lanes.PITCH)
			target_x = _anchor_x + sign_x * sin(_t * weave_frequency * TAU) * amp
		Shape.HOOK:
			# Shifter: hold the spawn lane until shift_delay AND the target lane is
			# clear, then lock a one-way commit (P2 lane-awareness). If the target
			# never clears the enemy simply rides its spawn lane down — no collision.
			if not _hook_committed:
				# Drifter (zone_timed): commit once inside the fire zone (band_progress
				# in (0, ZONE_COMMIT_MAX)). Shifter (timer): commit after shift_delay.
				var ready: bool
				if zone_timed:
					var bp: float = Zones.band_progress(enemy.position.y)
					ready = bp > 0.0 and bp < ZONE_COMMIT_MAX
				else:
					ready = _t >= shift_delay
				if ready and _hook_target_free(enemy, sign_x):
					_hook_committed = true
					_hook_commit_bp = Zones.band_progress(enemy.position.y)
					_hook_start_t = _t
				target_x = _anchor_x  # straight until committed
			else:
				var u: float
				if zone_timed:
					# Slide spans from the commit point to the band bottom, so even a
					# delayed commit still lands in the new lane by the fire-zone exit.
					var bp2: float = Zones.band_progress(enemy.position.y)
					u = clampf((bp2 - _hook_commit_bp) / maxf(1.0 - _hook_commit_bp, 0.0001), 0.0, 1.0)
				else:
					u = clampf((_t - _hook_start_t) / maxf(shift_duration, 0.0001), 0.0, 1.0)
				var eased: float = u * u * (3.0 - 2.0 * u)  # smoothstep ease-in-out
				target_x = _anchor_x + sign_x * float(shift_lanes) * Lanes.PITCH * eased
		Shape.DIVE_RETURN:
			# Dive straight down until the fire-zone midpoint, then curve into the adjacent
			# lane while climbing back UP and off the top. Returns its own full step (the
			# trailing return statement only covers the lateral-X shapes), since the vertical
			# direction reverses here.
			if not _return_started:
				if Zones.band_progress(enemy.position.y) >= return_trigger_bp:
					_return_started = true
					_return_t = 0.0
					_return_anchor_x = enemy.position.x
				return Vector2(0.0, down_speed * delta)   # dive down
			_return_t += delta
			var ru: float = clampf(_return_t / maxf(return_curve_time, 0.0001), 0.0, 1.0)
			var reased: float = ru * ru * (3.0 - 2.0 * ru)  # smoothstep
			var rtx: float = _return_anchor_x + sign_x * float(maxi(1, shift_lanes)) * Lanes.PITCH * reased
			return Vector2(rtx - enemy.position.x, -down_speed * delta)  # curve + climb out the top
		Shape.LANE_CUT:
			# Dive down until the fire-zone midpoint, then a rounded turn LEFT/RIGHT and run
			# HORIZONTALLY off the side (like DIVE_RETURN but exiting a side, not climbing up).
			if not _return_started:
				if Zones.band_progress(enemy.position.y) >= return_trigger_bp:
					_return_started = true
					_return_t = 0.0
				return Vector2(0.0, down_speed * delta)   # dive down
			_return_t += delta
			var cu: float = clampf(_return_t / maxf(return_curve_time, 0.0001), 0.0, 1.0)
			var cang: float = lerpf(0.0, PI * 0.5, cu * cu * (3.0 - 2.0 * cu))  # 0=down..PI/2=horizontal
			return Vector2(sign_x * sin(cang) * down_speed * delta, cos(cang) * down_speed * delta)
		Shape.STEP:
			if step_synced:
				# Coordinated row step: shared anchor-relative offset (lanes -> px).
				target_x = _anchor_x + _synced_offset(_t) * Lanes.PITCH
			else:
				target_x = _step_update(enemy, delta)
		_:
			target_x = _anchor_x
	return Vector2(target_x - enemy.position.x, down_speed * delta)


# Keep a weave from pushing the enemy out of the 216-px playfield band
# (s_curve.gd precedent). The conductor guarantees hooks land on real lanes;
# weave just needs to stay shootable.
func _clamp_amp(amp: float) -> float:
	var room: float = min(
		_anchor_x - (Playfield.X_MIN + 12.0),
		(Playfield.X_MAX - 12.0) - _anchor_x
	)
	return min(amp, max(room, 0.0))


# STEP: hold the current lane for hold_time, then hop step_lanes toward _step_dir
# over step_time (smoothstep), then hold again. step_pingpong reverses at the lane
# bounds; otherwise it advances and clamps. step_repeat=false does a single hop.
func _step_update(enemy, delta: float) -> float:
	_phase_t += delta
	if _step_phase == 0:  # holding
		if _phase_t >= hold_time and (step_repeat or not _stepped_once):
			var nxt: int = _next_step_lane()
			# Drifter: only slide if the target lane is clear (P2 lane-awareness);
			# otherwise hold this lane and re-check next cycle.
			if nxt != _cur_lane and LaneTraffic.is_lane_free(enemy.get_tree(), nxt, enemy.position.y, enemy):
				_from_x = Lanes.lane_center(_cur_lane)
				_to_x = Lanes.lane_center(nxt)
				_next_lane = nxt
				_step_phase = 1
				_phase_t = 0.0
			else:
				_phase_t = 0.0  # nowhere to hop / blocked; keep holding
		return Lanes.lane_center(_cur_lane)
	# hopping
	var u: float = clampf(_phase_t / maxf(step_time, 0.0001), 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	var x: float = lerpf(_from_x, _to_x, eased)
	if u >= 1.0:
		_cur_lane = _next_lane
		_stepped_once = true
		_step_phase = 0
		_phase_t = 0.0
	return x


# Shifter target-lane free check: the lane this hook would commit to (anchor +
# signed shift), clamped to the board. Free when no other enemy holds it near the
# enemy's current Y. shift_lanes == 0 is trivially free (no move).
func _hook_target_free(enemy, sign_x: float) -> bool:
	if shift_lanes == 0:
		return true
	var target: int = Lanes.clamp_lane(_anchor_lane + int(round(sign_x * float(shift_lanes))))
	if target == _anchor_lane:
		return true
	return LaneTraffic.is_lane_free(enemy.get_tree(), target, enemy.position.y, enemy)


# Coordinated row step (P2d): the shared, anchor-relative lateral offset (in lanes)
# at time t. Holds at 0 for hold_time, then hops one lane per (hold_time+step_time)
# cycle, reflecting within [lo, hi]. Deterministic & stateless, so every row member
# fed the same params + clock produces the SAME offset -> the row shifts in unison.
func _synced_offset(t: float) -> float:
	if step_offset_hi <= step_offset_lo:
		return 0.0
	if t < hold_time:
		return 0.0
	var cyc: float = hold_time + step_time
	var te: float = t - hold_time
	var k: int = int(floor(te / cyc))
	var frac: float = te - float(k) * cyc
	var before: float = float(_fold_offset(k))
	var after: float = float(_fold_offset(k + 1))
	if frac < step_time:
		var u: float = clampf(frac / maxf(step_time, 0.0001), 0.0, 1.0)
		return lerpf(before, after, u * u * (3.0 - 2.0 * u))  # smoothstep
	return after


# Integer offset after n hops: a reflected walk on [lo, hi] starting at 0 (the anchor,
# always inside the range since lo<=0<=hi) stepping by step_start_dir. Closed-form
# triangle fold — no per-frame simulation.
func _fold_offset(n: int) -> int:
	var rng: int = step_offset_hi - step_offset_lo
	if rng <= 0:
		return step_offset_lo
	var x: int = step_start_dir * n
	var m: int = posmod(x - step_offset_lo, 2 * rng)
	if m <= rng:
		return step_offset_lo + m
	return step_offset_lo + (2 * rng - m)


func path_phase_capable() -> bool:
	return true  # every shape descends at down_speed; band-Y is monotonic


func _next_step_lane() -> int:
	var cand: int = _cur_lane + _step_dir * maxi(1, step_lanes)
	if cand < 0 or cand >= Lanes.COUNT:
		if step_pingpong:
			_step_dir = -_step_dir
			cand = _cur_lane + _step_dir * maxi(1, step_lanes)
		cand = clampi(cand, 0, Lanes.COUNT - 1)
	return cand
