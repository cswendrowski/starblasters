extends EnemyBase
class_name EnemyBeamTurret

# Beam turret — child of EnemyCruiser. No independent movement.
# Locks aim on the player at windup start, then fires a directed beam.
# Beam widths are narrower than the full enemy_beam_shooter.

enum BeamState { IDLE, WINDUP, FIRING, COOLDOWN }

const IDLE_DURATION     := 2.0
const WINDUP_DURATION   := 3.0
const FIRING_DURATION   := 2.0
const COOLDOWN_DURATION := 3.0

const BEAM_DPS   := 3.0
const BEAM_REACH := 300.0
const HIT_RADIUS := 8.0

var _beam_state: int = BeamState.IDLE
var _state_timer: float = 0.0
var _beam_t: float = 0.0

var _aim_pos: Vector2 = Vector2.ZERO
var _aim_dir: Vector2 = Vector2.DOWN

var _beam_outer:     Line2D = null
var _beam_mid:       Line2D = null
var _beam_core:      Line2D = null
var _beam_telegraph: Line2D = null
var _dmg_accum: float = 0.0


func _ready() -> void:
	max_health   = 4
	bounty_value = 5
	auto_rotate  = false
	display_scale = 0.5
	super._ready()


func _process(delta: float) -> void:
	_tick_beam_state(delta)
	super._process(delta)


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
				_enter_windup()


func _enter_windup() -> void:
	_beam_state  = BeamState.WINDUP
	_state_timer = 0.0
	var player := find_player()
	if player:
		_aim_pos = player.global_position
		_aim_dir = (player.global_position - global_position).normalized()
		if _aim_dir.length_squared() < 0.001:
			_aim_dir = Vector2.DOWN
	else:
		_aim_dir = Vector2.DOWN
		_aim_pos = global_position + _aim_dir * BEAM_REACH


func _enter_firing() -> void:
	_beam_state  = BeamState.FIRING
	_state_timer = 0.0


func _enter_cooldown() -> void:
	_beam_state  = BeamState.COOLDOWN
	_state_timer = 0.0
	_dmg_accum   = 0.0


func _ensure_beam_visuals() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		return
	# Narrower than enemy_beam_shooter: outer=8, mid=5, core=2, telegraph=1
	_beam_outer     = _make_line(Color(0.65, 0.15, 1.0, 0.55), 8.0)
	_beam_mid       = _make_line(Color(1.0, 0.5, 0.1, 0.85),   5.0)
	_beam_core      = _make_line(Color(1.0, 0.95, 0.35, 1.0),  2.0)
	_beam_telegraph = _make_line(Color(1.0, 0.95, 0.35, 0.5),  1.0)
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
	# Use the locked aim position so the line stays pointing at the
	# world coordinate snapped at windup, not the current global_position
	# offset (which would drift as the cruiser parent moves).
	var endpoint := _aim_pos + _aim_dir * BEAM_REACH
	line.points = PackedVector2Array([Vector2.ZERO, to_local(endpoint)])


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
	# Segment: turret's current position → locked aim endpoint. This matches
	# the visual so the beam doesn't silently hit the player off-screen when
	# the cruiser drifts during the firing window.
	var seg_start := global_position
	var seg_end   := _aim_pos + _aim_dir * BEAM_REACH
	if _dist_point_to_segment(player.global_position, seg_start, seg_end) <= HIT_RADIUS:
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
