extends EnemyBase
class_name EnemyBeamShooter

enum BeamState { IDLE, WINDUP, FIRING, COOLDOWN }
enum PairPhase { ENTER, FIRE_IN, SEPARATE, FIRE_OUT, REGROUP }

const IDLE_DURATION    := 1.5
const WINDUP_DURATION  := 1.5   # halved (was 3.0)
const FIRING_DURATION  := 1.0   # halved (was 2.0)
const COOLDOWN_DURATION := 2.5

const SETTLE_Y         := 60.0
const ENTER_SPEED      := 220.0
const INNER_X_OFFSET   := 24.0
const OUTER_X_OFFSET   := 70.0
const LATERAL_SPEED    := 40.0
const X_ARRIVAL_EPS    := 1.0

const BEAM_DPS     := 3.0
const BEAM_REACH   := 300.0
const HIT_RADIUS   := 10.0

var _beam_state: int = BeamState.IDLE
var _state_timer: float = 0.0
var _beam_t: float = 0.0

var _aim_pos: Vector2 = Vector2.ZERO
var _aim_dir: Vector2 = Vector2.DOWN

var _pair_phase: int = PairPhase.ENTER
var _side_sign: int = -1  # -1 = left, +1 = right
var _side_resolved: bool = false

var _beam_outer:      Line2D = null
var _beam_mid:        Line2D = null
var _beam_core:       Line2D = null
var _beam_telegraph:  Line2D = null
var _dmg_accum:       float  = 0.0


func _ready() -> void:
	max_health    = 12
	bounty_value  = 30
	auto_rotate   = false
	super._ready()
	_resolve_side()


func _resolve_side() -> void:
	# Per-instance side. Wave generator may set "beam_pair_side" meta ("L"/"R"),
	# otherwise fall back to spawn-X position vs playfield centre.
	var side := "L"
	if has_meta("beam_pair_side"):
		side = str(get_meta("beam_pair_side"))
	else:
		side = "L" if global_position.x < Playfield.CENTER.x else "R"
	_side_sign = -1 if side == "L" else 1
	_side_resolved = true


func _process(delta: float) -> void:
	_move(delta)
	# Beam cycle only ticks during firing phases; phases choose when to enter
	# WINDUP via _enter_windup() so the visuals stay in sync with the cycle.
	if _pair_phase == PairPhase.FIRE_IN or _pair_phase == PairPhase.FIRE_OUT:
		_tick_beam_state(delta)
	else:
		_hide_all_beam_lines()
	super._process(delta)


func _inner_x() -> float:
	return Playfield.CENTER.x + float(_side_sign) * INNER_X_OFFSET


func _outer_x() -> float:
	return Playfield.CENTER.x + float(_side_sign) * OUTER_X_OFFSET


func _lerp_x_toward(target_x: float, delta: float) -> bool:
	# Move global_position.x toward target_x at LATERAL_SPEED. Returns true on arrival.
	var diff := target_x - global_position.x
	if absf(diff) <= X_ARRIVAL_EPS:
		global_position.x = target_x
		return true
	var step: float = LATERAL_SPEED * delta
	if absf(diff) <= step:
		global_position.x = target_x
		return true
	global_position.x += signf(diff) * step
	return false


func _move(delta: float) -> void:
	if _dying:
		return
	if not _side_resolved:
		_resolve_side()
	match _pair_phase:
		PairPhase.ENTER:
			if global_position.y < SETTLE_Y:
				global_position.y += ENTER_SPEED * delta
			else:
				global_position.y = SETTLE_Y
				_pair_phase = PairPhase.FIRE_IN
				_reset_beam_cycle()
		PairPhase.FIRE_IN:
			# Drift to inner X while firing cycle runs in _process.
			_lerp_x_toward(_inner_x(), delta)
		PairPhase.SEPARATE:
			if _lerp_x_toward(_outer_x(), delta):
				_pair_phase = PairPhase.FIRE_OUT
				_reset_beam_cycle()
		PairPhase.FIRE_OUT:
			_lerp_x_toward(_outer_x(), delta)
		PairPhase.REGROUP:
			if _lerp_x_toward(_inner_x(), delta):
				_pair_phase = PairPhase.FIRE_IN
				_reset_beam_cycle()


func _reset_beam_cycle() -> void:
	_beam_state = BeamState.IDLE
	_state_timer = 0.0
	_dmg_accum = 0.0
	_hide_all_beam_lines()


func _tick_beam_state(delta: float) -> void:
	_beam_t += delta
	_state_timer += delta

	match _beam_state:
		BeamState.IDLE:
			_hide_all_beam_lines()
			if _state_timer >= IDLE_DURATION:
				_enter_windup()

		BeamState.WINDUP:
			_ensure_beam_visuals()
			_set_beam_layers_visible(false, false, false, true)
			var alpha := sin(_beam_t * TAU * 2.0) * 0.2 + 0.5
			if _beam_telegraph:
				var c := _beam_telegraph.default_color
				c.a = alpha
				_beam_telegraph.default_color = c
				_update_line_points(_beam_telegraph)
			if _state_timer >= WINDUP_DURATION:
				_enter_firing()

		BeamState.FIRING:
			_ensure_beam_visuals()
			_set_beam_layers_visible(true, true, true, false)
			_update_line_points(_beam_outer)
			_update_line_points(_beam_mid)
			_update_line_points(_beam_core)
			_apply_beam_damage(delta)
			if _state_timer >= FIRING_DURATION:
				_enter_cooldown()

		BeamState.COOLDOWN:
			_hide_all_beam_lines()
			if _state_timer >= COOLDOWN_DURATION:
				# One fire cycle complete — advance the pair-cycle phase
				# instead of looping the beam locally. The new phase will
				# call _reset_beam_cycle() once it arrives at its X target.
				if _pair_phase == PairPhase.FIRE_IN:
					_pair_phase = PairPhase.SEPARATE
				elif _pair_phase == PairPhase.FIRE_OUT:
					_pair_phase = PairPhase.REGROUP
				_beam_state = BeamState.IDLE
				_state_timer = 0.0


func _enter_windup() -> void:
	_beam_state = BeamState.WINDUP
	_state_timer = 0.0


func _enter_firing() -> void:
	_beam_state = BeamState.FIRING
	_state_timer = 0.0


func _enter_cooldown() -> void:
	_beam_state = BeamState.COOLDOWN
	_state_timer = 0.0
	_dmg_accum = 0.0


func _ensure_beam_visuals() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		return
	_beam_outer = _make_line(Color(0.65, 0.15, 1.0, 0.55), 16.0)
	_beam_mid   = _make_line(Color(1.0, 0.5, 0.1, 0.85),   8.0)
	_beam_core  = _make_line(Color(1.0, 0.95, 0.35, 1.0),  3.0)
	_beam_telegraph = _make_line(Color(1.0, 0.95, 0.35, 0.5), 1.0)
	add_child.call_deferred(_beam_outer)
	add_child.call_deferred(_beam_mid)
	add_child.call_deferred(_beam_core)
	add_child.call_deferred(_beam_telegraph)


func _make_line(color: Color, width: float) -> Line2D:
	var l := Line2D.new()
	l.default_color = color
	l.width = width
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode   = Line2D.LINE_CAP_ROUND
	l.z_index = 4
	l.visible = false
	return l


func _update_line_points(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	line.points = PackedVector2Array([Vector2.ZERO, _aim_dir * BEAM_REACH])


func _set_beam_layers_visible(outer: bool, mid: bool, core: bool, telegraph: bool) -> void:
	if _beam_outer     and is_instance_valid(_beam_outer):     _beam_outer.visible     = outer
	if _beam_mid       and is_instance_valid(_beam_mid):       _beam_mid.visible       = mid
	if _beam_core      and is_instance_valid(_beam_core):      _beam_core.visible      = core
	if _beam_telegraph and is_instance_valid(_beam_telegraph): _beam_telegraph.visible = telegraph


func _hide_all_beam_lines() -> void:
	_set_beam_layers_visible(false, false, false, false)


func _apply_beam_damage(delta: float) -> void:
	var player := find_player()
	if player == null:
		return
	var seg_end := global_position + _aim_dir * BEAM_REACH
	if _dist_point_to_segment(player.global_position, global_position, seg_end) <= HIT_RADIUS:
		_dmg_accum += BEAM_DPS * delta
		while _dmg_accum >= 1.0:
			player.take_damage(1)
			_dmg_accum -= 1.0


static func _dist_point_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return pt.distance_to(a)
	var t := clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + ab * t)
