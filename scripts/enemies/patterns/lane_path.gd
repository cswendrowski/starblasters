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
# Speed naming: the descent export is `down_speed` (ends in `_speed`). Author it
# on a rung (mult of 60) under the 8 px/f clarity ceiling — enemy speeds are used
# as authored now (the +5%/sector locomotion scale was dropped 2026-06-23).

#   STEP      — hold a lane, hop step_lanes to a new lane, hold, repeat. Knobs:
#               hold_time, step_time, step_lanes (1 = adjacent), step_repeat (keep
#               hopping vs one hop), step_pingpong (reverse at edges vs advance).

const LaneTraffic = preload("res://scripts/systems/lane_traffic.gd")

#   DIVE_RETURN — dive down a lane; at the fire-zone midpoint, curve into the adjacent
#               lane (shift_lanes) AND reverse the descent to climb back UP and off the
#               top. For missile/rocket droppers: drop the volley on the way down, then
#               turn and burn off-screen. The "lane_hook" production key. Sets FREE_ANY_EDGE
#               in on_start so the top exit frees the enemy (CYCLE_BOTTOM never watches the top).
#   LANE_CUT  — dive down a lane; at the fire-zone midpoint, curve LEFT/RIGHT and run
#               HORIZONTALLY off the side. The "lane_cut" key. Also FREE_ANY_EDGE.
enum Shape { STRAIGHT, WEAVE, HOOK, STEP, DIVE_RETURN, LANE_CUT }

@export var shape: Shape = Shape.STRAIGHT
@export var mirrored: bool = false          # reflect lateral direction L<->R

@export_group("Hook")
@export var shift_lanes: int = 0            # signed lane delta for the one-way hook
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
# WEAVE state: hold the spawn lane until the depth gate, then wobble. _weave_t0 anchors the sine
# clock to the gate crossing so the swing starts from lane center (phase 0), not mid-swing.
var _weave_started: bool = false
var _weave_t0: float = 0.0
# Latest band_progress at which a zone-timed Drifter will still start a slide — past
# this there isn't enough band left to land in the new lane gracefully, so it rides
# its lane straight down instead.
const ZONE_COMMIT_MAX: float = 0.7
# Depth-gate fallbacks for when the enemy carries no depth (depth_bp < 0): chosen to preserve each
# shape's pre-gate behavior. WEAVE wobbled from the top (gate 0.0 = start immediately); SHIFT
# committed ~0.6s after entry (≈ band_progress 0.3). LANE_CUT/DIVE_RETURN keep return_trigger_bp.
# A depth authored on the enemy (or the Lane Visualizer's randomized high/mid/low) overrides these.
const WEAVE_GATE_DEFAULT: float = 0.0
const SHIFT_GATE_DEFAULT: float = 0.3
# LANE_CUT low-speed exit-angle scaling (Roman 2026-07-07). The exit leg's max turn angle from
# straight-down: at/above LANE_CUT_FULL_SPEED it's the full 90° (pure horizontal run-off = the tuned
# 120 px/s baseline, unchanged). Below it, the max angle eases DOWN toward LANE_CUT_MIN_EXIT_DEG so a
# slow chassis keeps a downward component and exits the bottom in bounded time instead of crawling
# sideways for seconds. Tunables Roman can adjust:
#   LANE_CUT_FULL_SPEED  — px/s at/above which the exit is unchanged (the small-chassis base rung).
#   LANE_CUT_MIN_EXIT_DEG — shallowest exit angle (deg from down) at/below creep speed; 55° keeps a
#                           solid downward component (cos 55° ≈ 0.57 of speed still descending) while
#                           still carrying the ship clearly off toward its cut side.
const LANE_CUT_FULL_SPEED: float = 120.0
const LANE_CUT_MIN_EXIT_DEG: float = 55.0
# DIVE_RETURN low-speed U-turn scaling (Roman 2026-07-07). Same fixed-distance-vs-speed root cause as
# LANE_CUT, but on the VERTICAL axis: the U-turn's climb-back-UP leg is a FIXED ~150px height, so a
# slow chassis spends seconds facing pure-backwards/up (a wrong-facing crawl). The terminal turn angle
# (measured from straight-DOWN) is the full 180° at/above DIVE_RETURN_FULL_SPEED — a straight-up climb
# off the top, the tuned 120 px/s baseline, unchanged. Below full speed it steps to DIVE_RETURN_MIN_EXIT_DEG
# (a fixed down-diagonal, cos>0 so it always descends out the BOTTOM in bounded time) — NOT a linear ramp
# up toward 180°, because DIVE_RETURN's full angle is 180° (up), so any ramp would pass through the >90°
# climbing region and reintroduce the crawl. Tunables Roman can adjust:
#   DIVE_RETURN_FULL_SPEED  — px/s at/above which the U-turn is unchanged (the small-chassis base rung).
#   DIVE_RETURN_MIN_EXIT_DEG — terminal angle (deg from down) for any sub-full chassis; 60° keeps a
#                              downward component (cos 60° = 0.5 of speed still descending) while the
#                              lateral throw still carries the ship clearly off toward its hook side.
const DIVE_RETURN_FULL_SPEED: float = 120.0
const DIVE_RETURN_MIN_EXIT_DEG: float = 60.0
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
	_weave_started = false
	_weave_t0 = 0.0
	_return_started = false
	_return_t = 0.0
	_return_anchor_x = _anchor_x
	# DIVE_RETURN climbs back up off the TOP, LANE_CUT runs off the SIDE — both need
	# FREE_ANY_EDGE so the exit frees the enemy (CYCLE_BOTTOM only watches bottom/side).
	# 1 = OffscreenMode.FREE_ANY_EDGE.
	if shape == Shape.DIVE_RETURN or shape == Shape.LANE_CUT:
		enemy.offscreen_mode = 1
	# LANE_CUT runs HORIZONTALLY off the side after its turn, so it must opt out of the
	# enemy_core side-clamp (mirrors side_traverse/side_turn) — otherwise X is pinned at
	# the band edge and the FREE_ANY_EDGE side-exit never fires (enemy gets stuck there).
	# DIVE_RETURN exits the TOP and should stay clamped through its dive+climb, so it is
	# deliberately left out.
	if shape == Shape.LANE_CUT:
		enemy.allow_side_exit = true


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	# Locomotion refactor 2026-06-19: descent speed + TURN-OFF depth are chassis/formation-owned.
	# `spd` replaces the vestigial down_speed export; `turn_bp` is where DIVE_RETURN/LANE_CUT turn
	# off (the lane_hook/lane_cut keys), defaulting to the pattern's return_trigger_bp.
	var spd: float = _move_speed(enemy)
	var turn_bp: float = _depth_bp(enemy, return_trigger_bp)
	var sign_x: float = -1.0 if mirrored else 1.0
	var target_x: float = _anchor_x
	match shape:
		Shape.WEAVE:
			# Depth-gated wobble: descend in the spawn lane until band_progress reaches the gate
			# (high/mid/low), THEN start the sinusoidal swing. _weave_t0 anchors the sine to the
			# gate crossing so the first swing leaves lane center cleanly (no mid-swing snap).
			var amp: float = _clamp_amp(absf(weave_lanes) * Lanes.PITCH)
			# No lateral until PAST the entry band (FIX #3): band_progress is 0.0 everywhere above
			# y=40, so the bp gate alone (default 0.0) latched on the spawn frame and the enemy swung
			# out of lane while still entering. Require it to clear Zones.ENTRY_END first. _weave_t0
			# anchors the sine clock to the gate crossing so the first swing still leaves lane center
			# cleanly (Roman's earlier phase-anchor fix, preserved).
			if not _weave_started \
					and enemy.position.y >= Zones.ENTRY_END \
					and Zones.band_progress(enemy.position.y) >= _depth_bp(enemy, WEAVE_GATE_DEFAULT):
				_weave_started = true
				_weave_t0 = _t
			if _weave_started:
				target_x = _anchor_x + sign_x * sin((_t - _weave_t0) * weave_frequency * TAU) * amp
			else:
				target_x = _anchor_x
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
					# Shifter: commit the one-way slide at the authored DEPTH gate (high/mid/low) —
					# hold the spawn lane until band_progress reaches it, then slide. Supersedes the
					# old fixed shift_delay timer so the commit depth is tunable per enemy.
					ready = Zones.band_progress(enemy.position.y) >= _depth_bp(enemy, SHIFT_GATE_DEFAULT)
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
				var eased: float = smoothstep(0.0, 1.0, u)  # ease-in-out
				# Slide to the inward-guarded destination lane (clamped into the inner band).
				target_x = _anchor_x + float(_hook_dest_lane(sign_x) - _anchor_lane) * Lanes.PITCH * eased
		Shape.DIVE_RETURN:
			# Dive straight down until the fire-zone midpoint, then a SMOOTH rounded U-turn:
			# ease the lateral into the adjacent lane AND ease the vertical velocity from
			# +down through 0 to -down so the descent ROUNDS into a climb instead of snapping
			# direction in one frame (Roman 2026-06-09: "needs a smooth, rounded turn, not a
			# sharp sudden change"). Apex (vy = 0) lands at reased = 0.5.
			if not _return_started:
				if Zones.band_progress(enemy.position.y) >= turn_bp:
					_return_started = true
					_return_t = 0.0
					_return_anchor_x = enemy.position.x
				return Vector2(0.0, spd * delta)   # dive down
			_return_t += delta
			var ru: float = clampf(_return_t / maxf(return_curve_time, 0.0001), 0.0, 1.0)
			var reased: float = smoothstep(0.0, 1.0, ru)
			var rtx: float = _return_anchor_x + sign_x * float(maxi(1, shift_lanes)) * Lanes.PITCH * reased
			# Low-speed graceful degrade (Roman 2026-07-07, mirrors LANE_CUT): the U-turn's terminal
			# heading used to HARD-lerp to -spd (a pure straight-UP climb off the top). At the tuned
			# small-chassis 120 px/s that reads fine (~1.25s climb, exits the top in ~2.75s). But with
			# `engine: -1` the chassis drops to 60 px/s and the FIXED-height climb back up (~150px)
			# doubles the on-screen time (~2.5s of pure BACKWARDS/up facing) — the same fixed-distance-
			# vs-speed-scaled degeneration LANE_CUT already fixes. Fix: cap the terminal turn angle
			# BELOW straight-up as speed drops, so a slow chassis keeps a DOWNWARD component and exits
			# the BOTTOM in bounded time (facing stays mostly down-lane) instead of crawling back up.
			# At/above DIVE_RETURN_FULL_SPEED the terminal angle is the full 180 deg (straight up) -> the
			# 120 px/s baseline is byte-identical. term_ang is from straight-DOWN, so vy sweeps from
			# +spd (down, angle 0) to cos(term_ang)*spd; at full speed term_ang=PI -> -spd (old form).
			var term_ang: float = _dive_return_term_angle(spd)
			var rvy: float = lerpf(spd, cos(term_ang) * spd, reased)  # +down -> ... -> terminal vy
			return Vector2(rtx - enemy.position.x, rvy * delta)
		Shape.LANE_CUT:
			# Dive down until the fire-zone midpoint, then a rounded turn LEFT/RIGHT and run
			# off the side (like DIVE_RETURN but exiting a side, not climbing up).
			#
			# Low-speed graceful degrade (Roman 2026-07-07): the exit used to ramp to a PURE
			# horizontal run (cang -> PI/2). At the tuned small-chassis 120 px/s that reads fine
			# (~0.7s of sideways run, exits the side in ~2.5s total). But with `engine: -1` the
			# chassis drops to 60 px/s and the DISTANCE-bound sideways leg doubles the on-screen
			# time (~4.75s) while facing sits at a dead 90/270 for ~2s — a wrong-facing crawl.
			# Fix: cap the exit angle BELOW horizontal as speed drops, keeping a downward
			# component so (a) the ship keeps progressing and exits the BOTTOM in bounded time,
			# and (b) facing stays mostly down-lane (diagonal, not pure sideways). At/above
			# LANE_CUT_FULL_SPEED the cap is the full 90° → the 120 px/s baseline is unchanged.
			if not _return_started:
				if Zones.band_progress(enemy.position.y) >= turn_bp:
					_return_started = true
					_return_t = 0.0
				return Vector2(0.0, spd * delta)   # dive down
			_return_t += delta
			var cu: float = clampf(_return_t / maxf(return_curve_time, 0.0001), 0.0, 1.0)
			var max_ang: float = _lane_cut_max_angle(spd)
			var cang: float = lerpf(0.0, max_ang, smoothstep(0.0, 1.0, cu))  # 0=down..max_ang
			return Vector2(sign_x * sin(cang) * spd * delta, cos(cang) * spd * delta)
		Shape.STEP:
			if step_synced:
				# Coordinated row step: shared anchor-relative offset (lanes -> px).
				target_x = _anchor_x + _synced_offset(_t) * Lanes.PITCH
			else:
				target_x = _step_update(enemy, delta)
		_:
			target_x = _anchor_x
	return Vector2(target_x - enemy.position.x, spd * delta)


# Keep a weave from pushing the enemy out of the 216-px playfield band
# (s_curve.gd precedent). The conductor guarantees hooks land on real lanes;
# weave just needs to stay shootable.
func _clamp_amp(amp: float) -> float:
	var room: float = min(
		_anchor_x - (Playfield.X_MIN + 12.0),
		(Playfield.X_MAX - 12.0) - _anchor_x
	)
	return min(amp, max(room, 0.0))


# LANE_CUT max exit angle (radians from straight-down) for a chassis moving at `spd` px/s. Full 90°
# at/above LANE_CUT_FULL_SPEED (baseline), easing to LANE_CUT_MIN_EXIT_DEG at/below creep so slow
# ships keep descending (bounded on-screen time, facing stays mostly down-lane). Linear in speed
# between creep and full — a monotone, predictable knob.
func _lane_cut_max_angle(spd: float) -> float:
	var full: float = PI * 0.5
	if spd >= LANE_CUT_FULL_SPEED:
		return full
	var lo: float = Clarity.CREEP_SPEED
	var t: float = clampf((spd - lo) / maxf(LANE_CUT_FULL_SPEED - lo, 0.0001), 0.0, 1.0)
	return lerpf(deg_to_rad(LANE_CUT_MIN_EXIT_DEG), full, t)


# DIVE_RETURN terminal U-turn angle (radians from straight-DOWN) for a chassis at `spd` px/s. Full PI
# (180°, straight-up climb off the top) at/above DIVE_RETURN_FULL_SPEED — the tuned baseline, byte-
# identical. Eases DOWN toward DIVE_RETURN_MIN_EXIT_DEG at/below creep so a slow ship keeps a downward
# component (bounded bottom exit, facing stays mostly down-lane). Linear in speed between creep and
# full — a monotone, predictable knob (mirrors _lane_cut_max_angle).
func _dive_return_term_angle(spd: float) -> float:
	# At/above full speed: the tuned 180° straight-up climb (baseline, byte-identical). ANY speed below
	# full degrades to a bounded DOWNWARD exit: clamp the terminal angle at DIVE_RETURN_MIN_EXIT_DEG
	# (a fixed down-diagonal, cos>0 so it always descends out the bottom). We do NOT interpolate up
	# toward 180° below full speed — unlike LANE_CUT (whose full is only 90°/horizontal), DIVE_RETURN's
	# full is 180°/up, so any linear ramp would pass through the >90° "climbing-up" region and reintroduce
	# the slow backwards crawl for a slow chassis. A hard step (down-diagonal below full, up-climb at
	# full) keeps every sub-full rung strictly descending + bounded, which is the whole point.
	if spd >= DIVE_RETURN_FULL_SPEED:
		return PI   # straight up (180° from down) — the tuned baseline
	return deg_to_rad(DIVE_RETURN_MIN_EXIT_DEG)


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
	var target: int = _hook_dest_lane(sign_x)
	if target == _anchor_lane:
		return true
	return LaneTraffic.is_lane_free(enemy.get_tree(), target, enemy.position.y, enemy)


# The HOOK/Drifter destination lane, GUARDED inward (Roman 2026-06-11): an enemy on or
# near an outer lane (0/1 or COUNT-2/COUNT-1) hooks toward centre instead of drifting off
# the band, and the destination is always clamped into the inner band [1, COUNT-2].
func _hook_dest_lane(sign_x: float) -> int:
	var sx: float = sign_x
	if _anchor_lane <= 1:
		sx = 1.0                       # left edge → hook right (inward)
	elif _anchor_lane >= Lanes.COUNT - 2:
		sx = -1.0                      # right edge → hook left (inward)
	return clampi(_anchor_lane + int(round(sx * float(shift_lanes))), 1, Lanes.COUNT - 2)


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
	# DIVE_RETURN climbs back up off the top and LANE_CUT runs horizontally off the side — both
	# break band-Y monotonicity, so they must NOT auto-enable path-phase firing (they fire on the
	# standard timer instead). STRAIGHT/WEAVE/HOOK/STEP all descend monotonically at down_speed.
	return shape != Shape.DIVE_RETURN and shape != Shape.LANE_CUT


# Ship-kinematics fidelity (roadmap P1.5 — 2026-07-02). STEP hops yaw the hull ~60° and back each
# 0.25s hop, which reads as a snap; filter the LATERAL component only so the hop banks like a ship
# while the descent Y stays raw (path-phase firing predicts from descent speed — spec §7 constraint
# 3) and the lane X stays inside the <4px LaneTraffic free-check bound (ShipKinematics.LANE_LAT_ACCEL
# is sized for a 30px/0.25s hop; enemy_core additionally snaps any residual past LANE_LAT_MAX_ERR).
# All OTHER shapes stay EXACT: WEAVE/HOOK/DIVE_RETURN/LANE_CUT already ease their own transitions with
# smoothstep and their lateral geometry is authored/mirror-sacred — no snap to fix, and lane free-
# checks + mirror symmetry must see the exact closed-form position.
func fidelity() -> int:
	return ShipKinematics.Fidelity.EXACT_Y_SMOOTH_X if shape == Shape.STEP else ShipKinematics.Fidelity.EXACT


func _next_step_lane() -> int:
	var cand: int = _cur_lane + _step_dir * maxi(1, step_lanes)
	if cand < 0 or cand >= Lanes.COUNT:
		if step_pingpong:
			_step_dir = -_step_dir
			cand = _cur_lane + _step_dir * maxi(1, step_lanes)
		cand = clampi(cand, 0, Lanes.COUNT - 1)
	return cand
