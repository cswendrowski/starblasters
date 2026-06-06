extends EnemyBase
class_name EnemyBeamShooter

# Beamer — beam specialist modelled on the gunship's "arrive, settle, sweep" rhythm.
# Descends to a settle band, then sweeps left↔right while a BeamEmitter runs a
# telegraph → fire → cooldown cycle from its emitter marker.
#
# AIMING IS BY ROTATING THE HULL (gunship-style): the beam always exits the sprite's
# FRONT (local -Y) and the whole ship turns so the front points where it fires. The
# BeamEmitter draws LOCAL_FORWARD, so the hull's rotation aims it for free.
#
# Three aim behaviors (Roman 2026-06-06):
#   SWEEP — face straight down; the left↔right sweep rakes the beam.
#   CHASE — continuously rotate to track the player (turn rate kept slightly below the
#           player's so they can stay ahead — never a guaranteed hit).
#   LOCK  — track the player BETWEEN shots, but freeze rotation while the beam is
#           committed (telegraph + fire), then re-aim. Gives an evade window. Same idea
#           as the beam turret/cruiser (which locks its aim at windup).
#
# M6a.2 step 4b: the bespoke 4-layer Line2D + windup→fire FSM + segment-distance
# damage (~120 lines) were replaced by a single configured BeamEmitter node. This
# script now owns ONLY locomotion + aiming; the beam is the shared component.

const BeamEmitter = preload("res://scripts/enemies/beam_emitter.gd")

enum AimBehavior { SWEEP, CHASE, LOCK }
@export var aim_behavior: int = AimBehavior.SWEEP

enum GState { ENTER, ACTIVE }

# --- Locomotion ----------------------------------------------------------
const SETTLE_Y    := 58.0
const ENTER_SPEED := 170.0
const SWEEP_SPEED := 42.0
const SWEEP_MARGIN := 22.0   # keep the hull off the gutter edges
# rad/s hull turn rate (CHASE/LOCK). Kept below a focused player's turn-around so a
# CHASE beamer can be out-run (Roman 2026-06-06: reduced from 1.8).
const ROTATION_SPEED := 1.3

# Forward (nose) direction in the sprite's LOCAL frame — the beam exits here.
const FWD_LOCAL := Vector2(0.0, -1.0)

# --- Sibling spacing -----------------------------------------------------
const SPACING_RADIUS := 32.0
const PUSH_STRENGTH  := 60.0

var _state: int = GState.ENTER
var _sweep_dir: int = 1
var _target_x: float = 0.0
var _emitter_local: Vector2 = Vector2(0.0, -8.0)  # the "maw" at the sprite front
var _beam: Node = null


func _ready() -> void:
	max_health = 12
	bounty_value = 30
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	var em := get_node_or_null("BeamEmitter") as Marker2D
	if em != null:
		_emitter_local = em.position
	# Start already pointing down (front/maw toward the player below).
	rotation = PI
	# Sweep outward from spawn side so a pair fans apart rather than overlapping.
	_sweep_dir = -1 if global_position.x < Playfield.CENTER.x else 1
	_target_x = (Playfield.X_MIN + SWEEP_MARGIN) if _sweep_dir < 0 else (Playfield.X_MAX - SWEEP_MARGIN)
	# The shared beam — LOCAL_FORWARD so the hull's rotation aims it. Same cadence,
	# reach, dps + default purple/orange/yellow layers as the old bespoke beam.
	_beam = BeamEmitter.new()
	_beam.configure({
		"idle_time": 0.9, "windup_time": 1.3, "firing_time": 1.1, "cooldown_time": 1.5,
		"cycle": BeamEmitter.Cycle.LOOP_IDLE, "autostart": false,
		"endpoint": BeamEmitter.Endpoint.RAY, "aim_mode": BeamEmitter.AimMode.LOCAL_FORWARD,
		"forward_local": FWD_LOCAL, "reach": 320.0, "dps": 3.0, "hit_radius": 8.0,
		"emitter_offset": _emitter_local, "target_group": "player",
	})
	add_child(_beam)


func _process(delta: float) -> void:
	if _dying:
		return
	match _state:
		GState.ENTER:
			global_position.y += ENTER_SPEED * delta
			if global_position.y >= SETTLE_Y:
				global_position.y = SETTLE_Y
				_state = GState.ACTIVE
				if _beam != null:
					_beam.begin()   # start firing only once settled
		GState.ACTIVE:
			_do_sweep(delta)
	_face_target(delta)
	_repel_siblings(delta)
	super._process(delta)


# Rotate the hull so its front (FWD_LOCAL) points at the aim target. The beam (a child
# of the hull) is carried along, so it always exits the front. Behavior:
#   SWEEP — always face down. CHASE — always track the player. LOCK — track only when
#   the beam is NOT committed (held during telegraph + fire, then re-aims).
func _face_target(delta: float) -> void:
	var dir: Vector2 = Vector2.DOWN
	match aim_behavior:
		AimBehavior.SWEEP:
			dir = Vector2.DOWN
		AimBehavior.CHASE:
			dir = _player_dir()
		AimBehavior.LOCK:
			if _beam != null and is_instance_valid(_beam) and _beam.is_committed():
				return   # rotation frozen while committed — the evade window
			dir = _player_dir()
	var target_rot: float = atan2(dir.x, -dir.y)
	var diff: float = angle_difference(rotation, target_rot)
	rotation += clampf(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)


func _player_dir() -> Vector2:
	var player := find_player()
	if player != null:
		var d: Vector2 = player.global_position - global_position
		if d.length_squared() > 1.0:
			return d.normalized()
	return Vector2.DOWN


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
