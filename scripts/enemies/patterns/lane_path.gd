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

enum Shape { STRAIGHT, WEAVE, HOOK, STEP }

@export var shape: Shape = Shape.STRAIGHT
@export var down_speed: float = 120.0       # px/s descent (rung 2). Clarity-clamped.
@export var mirrored: bool = false          # reflect lateral direction L<->R

@export_group("Hook")
@export var shift_lanes: int = 0            # signed lane delta for the one-way hook
@export var shift_delay: float = 0.0        # s to hold the spawn lane before hooking
@export var shift_duration: float = 0.8     # s the hook transition takes

@export_group("Weave")
@export var weave_lanes: float = 1.0        # swing amplitude in lanes (+/-)
@export var weave_frequency: float = 0.8    # swings per second

@export_group("Step")
@export var hold_time: float = 0.8          # s to hold a lane before hopping
@export var step_time: float = 0.25         # s for the lateral hop between lanes
@export var step_lanes: int = 1             # lanes per hop (1 = adjacent)
@export var step_repeat: bool = true        # keep hopping (false = one hop then hold)
@export var step_pingpong: bool = true      # reverse at edges (false = advance + clamp)

var _t: float = 0.0
var _anchor_x: float = 0.0
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


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var sign_x: float = -1.0 if mirrored else 1.0
	var target_x: float = _anchor_x
	match shape:
		Shape.WEAVE:
			var amp: float = _clamp_amp(absf(weave_lanes) * Lanes.PITCH)
			target_x = _anchor_x + sign_x * sin(_t * weave_frequency * TAU) * amp
		Shape.HOOK:
			var u: float = clampf((_t - shift_delay) / maxf(shift_duration, 0.0001), 0.0, 1.0)
			var eased: float = u * u * (3.0 - 2.0 * u)  # smoothstep ease-in-out
			target_x = _anchor_x + sign_x * float(shift_lanes) * Lanes.PITCH * eased
		Shape.STEP:
			target_x = _step_update(delta)
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
func _step_update(delta: float) -> float:
	_phase_t += delta
	if _step_phase == 0:  # holding
		if _phase_t >= hold_time and (step_repeat or not _stepped_once):
			var nxt: int = _next_step_lane()
			if nxt != _cur_lane:
				_from_x = Lanes.lane_center(_cur_lane)
				_to_x = Lanes.lane_center(nxt)
				_next_lane = nxt
				_step_phase = 1
				_phase_t = 0.0
			else:
				_phase_t = 0.0  # nowhere to hop; keep holding
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
