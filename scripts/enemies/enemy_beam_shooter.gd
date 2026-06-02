extends EnemyBase
class_name EnemyBeamShooter

# Beamer — beam specialist modelled on the gunship's "arrive, settle, sweep"
# rhythm. Roman 2026-06-01 rework (was a two-ship "pair dance").
#
# It descends to a settle band, then sweeps left↔right while running a
# telegraph → fire → cooldown beam cycle from its BeamEmitter marker. The beam
# is a 4-layer Line2D stack (outer glow / mid / bright core), 10 px at its
# widest, matching the core style of the other enemy beams.
#
# AIMING IS DONE BY ROTATING THE HULL (gunship-style), NOT by steering the beam
# vector. The beam always fires straight out the sprite's FRONT (the emitter
# "maw" between the claws → local -Y), and the whole ship turns so that front
# points where it wants to fire. Two variants via the `aim_at_player` export
# (one scene per variant in the roster, like the gunship's role scenes):
#   false  — the hull faces straight DOWN; the sweep rakes the beam across.
#   true   — the hull smoothly ROTATES to track the player while sweeping; the
#            beam exits the front toward them. Rotation is speed-limited so the
#            track stays dodgeable.
#
# Bespoke (extends EnemyBase): the beam bypasses the shoot_pattern system, so
# the roster entries use shoot: null and the director leaves firing to us.

@export var aim_at_player: bool = false

enum GState { ENTER, ACTIVE }
enum BeamState { IDLE, WINDUP, FIRING, COOLDOWN }

# --- Locomotion ----------------------------------------------------------
const SETTLE_Y    := 58.0
const ENTER_SPEED := 170.0
const SWEEP_SPEED := 42.0
const SWEEP_MARGIN := 22.0   # keep the hull off the gutter edges
const ROTATION_SPEED := 1.8  # rad/s hull turn rate (player-tracking variant)

# --- Beam cycle ----------------------------------------------------------
const IDLE_DURATION     := 0.9
const WINDUP_DURATION   := 1.3
const FIRING_DURATION   := 1.1
const COOLDOWN_DURATION := 1.5

# --- Beam damage ---------------------------------------------------------
const BEAM_DPS   := 3.0
const BEAM_REACH := 320.0
const HIT_RADIUS := 8.0

# --- Beam visuals (widest layer = 10 px) ---------------------------------
const W_OUTER := 10.0
const W_MID   := 6.0
const W_CORE  := 3.5
const W_TELE  := 1.5
# Forward (nose) direction in the sprite's LOCAL frame — the beam exits here.
const FWD_LOCAL := Vector2(0.0, -1.0)

# --- Sibling spacing -----------------------------------------------------
const SPACING_RADIUS := 32.0
const PUSH_STRENGTH  := 60.0

var _state: int = GState.ENTER
var _beam_state: int = BeamState.IDLE
var _state_timer: float = 0.0
var _beam_t: float = 0.0

var _sweep_dir: int = 1
var _target_x: float = 0.0
var _emitter_local: Vector2 = Vector2(0.0, -8.0)  # the "maw" at the sprite front

var _dmg_accum: float = 0.0
var _beam_outer: Line2D = null
var _beam_mid: Line2D = null
var _beam_core: Line2D = null
var _beam_telegraph: Line2D = null


func _ready() -> void:
	max_health = 12
	bounty_value = 30
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	var em := get_node_or_null("BeamEmitter") as Marker2D
	if em != null:
		_emitter_local = em.position
	# Start already pointing down (front/maw toward the player below) so it isn't
	# born facing up; the per-frame _face_target then tracks from here.
	rotation = PI
	# Sweep outward from spawn side so a pair fans apart rather than overlapping.
	_sweep_dir = -1 if global_position.x < Playfield.CENTER.x else 1
	_target_x = (Playfield.X_MIN + SWEEP_MARGIN) if _sweep_dir < 0 else (Playfield.X_MAX - SWEEP_MARGIN)


func _process(delta: float) -> void:
	if _dying:
		return
	match _state:
		GState.ENTER:
			global_position.y += ENTER_SPEED * delta
			if global_position.y >= SETTLE_Y:
				global_position.y = SETTLE_Y
				_state = GState.ACTIVE
		GState.ACTIVE:
			_do_sweep(delta)
			_tick_beam_state(delta)
	_face_target(delta)
	_repel_siblings(delta)
	super._process(delta)


# Rotate the hull so its front (FWD_LOCAL) points at the aim target — straight
# down for the aim-down variant, or smoothly toward the player for the tracker.
# Speed-limited so tracking stays dodgeable. The beam (a child of the hull) is
# carried along, so it always exits the front.
func _face_target(delta: float) -> void:
	var dir: Vector2 = Vector2.DOWN
	if aim_at_player:
		var player := find_player()
		if player != null:
			var d: Vector2 = player.global_position - global_position
			if d.length_squared() > 1.0:
				dir = d.normalized()
	# rotation r such that FWD_LOCAL.rotated(r) == dir.
	var target_rot: float = atan2(dir.x, -dir.y)
	var diff: float = angle_difference(rotation, target_rot)
	rotation += clampf(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)


func _do_sweep(delta: float) -> void:
	var dx: float = _target_x - global_position.x
	if absf(dx) < 2.0:
		_sweep_dir = -_sweep_dir
		_target_x = (Playfield.X_MIN + SWEEP_MARGIN) if _sweep_dir < 0 else (Playfield.X_MAX - SWEEP_MARGIN)
	global_position.x += float(_sweep_dir) * SWEEP_SPEED * delta
	global_position.x = clampf(global_position.x, Playfield.X_MIN + SWEEP_MARGIN, Playfield.X_MAX - SWEEP_MARGIN)


# Push apart from any other beamer within SPACING_RADIUS so sweeps don't stack.
func _repel_siblings(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node):
			continue
		if node.get_script() != get_script():
			continue
		var diff: Vector2 = global_position - (node as Node2D).global_position
		var dist: float = diff.length()
		if dist < SPACING_RADIUS and dist > 0.001:
			global_position += diff.normalized() * PUSH_STRENGTH * delta
	global_position = Playfield.clamp_pos(global_position, 8.0)


# ---------------------------------------------------------------------------
# Beam cycle
# ---------------------------------------------------------------------------
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
			var a: float = sin(_beam_t * TAU * 2.0) * 0.2 + 0.5
			if _beam_telegraph:
				var c := _beam_telegraph.default_color
				c.a = a
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
	_beam_outer     = _make_line(Color(0.65, 0.15, 1.0, 0.55), W_OUTER)
	_beam_mid       = _make_line(Color(1.0, 0.5, 0.1, 0.85),  W_MID)
	_beam_core      = _make_line(Color(1.0, 0.95, 0.35, 1.0), W_CORE)
	_beam_telegraph = _make_line(Color(1.0, 0.95, 0.35, 0.5), W_TELE)
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


# The lines are children of the hull, so they're authored in LOCAL space and
# the hull's rotation aims them. The beam always runs from the emitter straight
# out the front (FWD_LOCAL); turning the ship turns the beam.
func _update_line_points(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	line.points = PackedVector2Array([_emitter_local, _emitter_local + FWD_LOCAL * BEAM_REACH])


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
	var seg_start: Vector2 = to_global(_emitter_local)
	var seg_end: Vector2 = to_global(_emitter_local + FWD_LOCAL * BEAM_REACH)
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
