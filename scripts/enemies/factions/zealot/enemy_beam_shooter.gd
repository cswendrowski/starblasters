extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyBeamShooter

# Beamer — beam specialist. On-lane migration 2026-06-08: LOCOMOTION is now on the lane system.
# The SWEEP variant uses the LoiterSweep movement pattern (descend → rake L↔R; renamed from
# "beam_sweep" 2026-06-09); the CHASE/LOCK tracker variant uses Drift (descend → hold). The beam
# itself is already the shared BeamEmitter
# (M6a.2). What stays bespoke is the hull-AIM (the beam exits the sprite front, so the hull turns
# to aim) — genuinely special: LOCK freezes rotation while the beam is committed.
#
# Three aim behaviors:
#   SWEEP — face down; the body sweep rakes the beam.
#   CHASE — rotate to track the player (turn rate below the player's so they can out-run it).
#   LOCK  — track between shots, freeze while the beam is committed (an evade window).

const BeamEmitter = preload("res://scripts/enemies/beam_emitter.gd")
const LoiterSweep = preload("res://scripts/enemies/patterns/loiter_sweep.gd")
const Drift = preload("res://scripts/enemies/patterns/drift.gd")

enum AimBehavior { SWEEP, CHASE, LOCK }
@export var aim_behavior: int = AimBehavior.SWEEP

const SETTLE_Y    := 58.0
const ROTATION_SPEED := 1.3              # rad/s hull turn (CHASE/LOCK)
const FWD_LOCAL := Vector2(0.0, -1.0)    # nose (beam exit) in local frame
const SPACING_RADIUS := 32.0
const PUSH_STRENGTH  := 60.0

var _emitter_local: Vector2 = Vector2(0.0, -8.0)
# _beam is inherited from enemy_core (its per-enemy BeamEmitter slot). shoot_pattern is null
# here, so enemy_core never auto-attaches one — we own it.
var _beam_started: bool = false


func _ready() -> void:
	max_health = 12
	bounty_value = 30
	auto_rotate = false                       # the hull-aim owns rotation
	offscreen_mode = OffscreenMode.NONE       # holds until destroyed
	var em := get_node_or_null("BeamEmitter") as Marker2D
	if em != null:
		_emitter_local = em.position
	rotation = PI                             # front/maw toward the player below
	# Locomotion fallback (the matrix assigns loiter_sweep / drift_high). SWEEP rakes; the
	# tracker variants hold and aim.
	if movement == null:
		if aim_behavior == AimBehavior.SWEEP:
			var m := LoiterSweep.new()
			m.settle_y = SETTLE_Y
			movement = m
		else:
			var d := Drift.new()
			d.hover_y = SETTLE_Y
			d.jiggle_px = 0.0
			movement = d
	super._ready()
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
	super._process(delta)        # movement pattern (LoiterSweep / Drift) + components
	if _dying:
		return
	# Start the beam once settled (works for both the sweep + hold movements).
	if not _beam_started and global_position.y >= SETTLE_Y - 0.5:
		if _beam != null:
			_beam.begin()
		_beam_started = true
	_face_target(delta)
	_repel_siblings(delta)


# Rotate the hull so its front (FWD_LOCAL) points at the aim target.
func _face_target(delta: float) -> void:
	var dir: Vector2 = Vector2.DOWN
	match aim_behavior:
		AimBehavior.SWEEP:
			dir = Vector2.DOWN
		AimBehavior.CHASE:
			dir = _player_dir()
		AimBehavior.LOCK:
			if _beam != null and is_instance_valid(_beam) and _beam.is_committed():
				return   # frozen while committed — the evade window
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
