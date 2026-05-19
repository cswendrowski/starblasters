extends "res://scripts/enemies/movement_pattern.gd"

# Inertial thrust. Newtonian zero-g feel: thrust is applied in impulses
# along the current facing, and changing direction requires rotating (slow)
# THEN thrusting. No drag — momentum carries. Reads as a slippery,
# overshoot-y, slow-to-stop heavy fighter.
#
# Tactic loop:
#   - Pick a target point (player-relative, jittered).
#   - Rotate the body toward the target at rotate_speed (degrees/sec).
#   - Once the body is roughly aligned, apply forward thrust.
#   - When close to the target, point AWAY and brake-thrust to bleed
#     velocity ("retro-burn").

# Roman, 2026-05-17 Movement Lab feedback: "Inertial should be more
# aggressively attempting to adjust itself as it flies, trying to keep
# its nose pointed at the player." Bumped rotate_speed 90 -> 200 and
# halved face_tolerance so it commits to thrust earlier.
@export var max_speed: float = 150.0
@export var thrust: float = 280.0
@export var brake_thrust: float = 360.0
@export var rotate_speed: float = 240.0       # degrees / sec
@export var face_tolerance_deg: float = 12.0
@export var brake_range: float = 60.0
# Harassment tuning (Roman 2026-05-18): tighter stand-off, faster target
# refresh so the ship re-commits at the player more often.
@export var target_range: float = 110.0
@export var target_refresh_min: float = 0.5
@export var target_refresh_max: float = 1.1
# When idle (between target refreshes), still rotate toward the player so
# the ship is always lined up for the next thrust burst.
@export var aim_at_player_idle: bool = true

var _vel: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _target_t: float = 0.0
var _target_period: float = 1.8


func on_start(enemy) -> void:
	_vel = Vector2.ZERO
	if enemy is Node2D:
		_target = enemy.position
	_target_t = 0.0
	_target_period = randf_range(target_refresh_min, target_refresh_max)


func compute_step(enemy, delta: float) -> Vector2:
	var player := _find_player(enemy)

	# Pick a fresh target relative to the player at intervals.
	_target_t += delta
	if _target_t >= _target_period and player:
		_target_t = 0.0
		_target_period = randf_range(target_refresh_min, target_refresh_max)
		var jitter: Vector2 = Vector2(randf_range(-48.0, 48.0), randf_range(-28.0, 28.0))
		var to_p: Vector2 = player.global_position - enemy.global_position
		var dir: Vector2 = to_p.normalized() if to_p.length() > 0.01 else Vector2(0, 1)
		_target = player.global_position - dir * target_range + jitter

	# Vector to target.
	var to_target: Vector2 = _target - enemy.global_position
	var dist: float = to_target.length()
	var dir_to_target: Vector2 = to_target.normalized() if dist > 0.01 else Vector2(0, 1)

	# Wall-collision lookahead — Roman, 2026-05-17 Movement Lab v2:
	# "Inertial needs to use a ray to periodically check where it's going
	# and counter-thrust to avoid collision with scene walls." Project the
	# current velocity LOOKAHEAD seconds and if that lands us off-canvas,
	# override thrust to point back into the playfield.
	const LOOKAHEAD: float = 0.6
	const WALL_BUFFER: float = 18.0
	# Horizontal walls = 216-wide playfield band; vertical = full viewport.
	var vp: Vector2 = enemy.get_viewport_rect().size
	var future: Vector2 = enemy.global_position + _vel * LOOKAHEAD
	var wall_avoid: Vector2 = Vector2.ZERO
	if future.x < Playfield.X_MIN + WALL_BUFFER:
		wall_avoid.x += 1.0
	elif future.x > Playfield.X_MAX - WALL_BUFFER:
		wall_avoid.x -= 1.0
	if future.y < WALL_BUFFER:
		wall_avoid.y += 1.0
	elif future.y > vp.y - WALL_BUFFER:
		wall_avoid.y -= 1.0

	# Decide thrust direction: approach if far, retro-burn if close,
	# OR counter-thrust if a wall is in the lookahead path.
	var thrust_dir: Vector2 = dir_to_target
	var thrust_mag: float = thrust
	if wall_avoid != Vector2.ZERO:
		thrust_dir = wall_avoid.normalized()
		thrust_mag = brake_thrust
	elif dist < brake_range:
		# Point the nose AWAY from target so retro-thrust kills velocity.
		thrust_dir = -dir_to_target
		thrust_mag = brake_thrust

	# Rotate the body toward thrust_dir at limited angular speed.
	if enemy is Node2D:
		var target_angle: float = thrust_dir.angle() + PI * 0.5  # sprite faces +Y
		var current: float = enemy.rotation
		var diff: float = wrapf(target_angle - current, -PI, PI)
		var max_step: float = deg_to_rad(rotate_speed) * delta
		if abs(diff) <= max_step:
			enemy.rotation = target_angle
		else:
			enemy.rotation += sign(diff) * max_step
		if "auto_rotate" in enemy:
			enemy.auto_rotate = false

	# Only apply thrust if the body is roughly aligned with thrust_dir.
	var body_forward: Vector2 = Vector2.ZERO
	if enemy is Node2D:
		# Sprite faces +Y when rotation=0, so forward = (sin(rot), -cos(rot))
		# wait — Godot rotation rotates +Y into (-sin, cos). Simpler: derive
		# from rotation directly.
		var rot: float = enemy.rotation - PI * 0.5
		body_forward = Vector2(cos(rot), sin(rot))
	var alignment: float = body_forward.dot(thrust_dir)
	if alignment >= cos(deg_to_rad(face_tolerance_deg)):
		_vel += body_forward * thrust_mag * delta

	# Cap to max_speed. No drag — Newtonian.
	if _vel.length() > max_speed:
		_vel = _vel.normalized() * max_speed

	return _vel * delta


func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
