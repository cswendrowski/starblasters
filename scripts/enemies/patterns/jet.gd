extends "res://scripts/enemies/movement_pattern.gd"

# Atmospheric-flight model. Constant forward speed (no full stop), with
# turn rate that SHRINKS at high speed — high speed = wide arcs. A slight
# baseline weave keeps the path interesting even on a straight approach.
# Same shape works for guided missiles (high min_speed, narrow turn) and
# heavy bombers (low min_speed, slow turns).
#
# Tactic loop:
#   - Always move forward along facing at current speed.
#   - Apply yaw rate toward (player - position), scaled inversely to speed.
#   - Sinusoidal micro-weave on top of the yaw to break up linear paths.

@export var min_speed: float = 90.0
@export var max_speed: float = 200.0
@export var accel: float = 60.0               # how fast speed adjusts toward the target speed
# Yaw rate at min_speed (degrees/sec). At max_speed, this gets multiplied
# by `turn_speed_falloff`.
@export var turn_rate_at_min: float = 200.0
@export var turn_speed_falloff: float = 0.35   # turn_rate(max_speed) = turn_rate_at_min × falloff
@export var weave_amplitude_deg: float = 8.0   # baseline sinusoidal yaw
@export var weave_freq: float = 1.6
@export var target_speed: float = 160.0
# Pull the enemy back into the play field when it strays past these bounds.
@export var playfield_margin: float = 16.0

var _speed: float = 0.0
var _t: float = 0.0


func on_start(_enemy) -> void:
	_speed = target_speed
	_t = 0.0


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var player := _find_player(enemy)
	# Wall-proximity speed scale: when near an edge, target a slower
	# cruise speed so the turn rate (which is highest at low speed) lets
	# us pivot away (Roman, 2026-05-17: "Jet should slow down, thus
	# getting a tighter turn radius, so that it can avoid walls better").
	var vp: Vector2 = enemy.get_viewport_rect().size
	var near_wall_x: float = min(enemy.position.x, vp.x - enemy.position.x)
	var near_wall_y: float = min(enemy.position.y, vp.y - enemy.position.y)
	var near_wall: float = min(near_wall_x, near_wall_y)
	var wall_band: float = 48.0
	var wall_factor: float = clamp(near_wall / wall_band, 0.0, 1.0)
	var effective_target: float = lerp(min_speed, target_speed, wall_factor)
	# Ease speed toward effective target — bleed off near walls, cruise far.
	_speed = move_toward(_speed, effective_target, accel * delta)
	_speed = clamp(_speed, min_speed, max_speed)

	# Compute desired heading.
	var desired_dir: Vector2 = Vector2(0, 1)
	if player:
		var to_p: Vector2 = player.global_position - enemy.global_position
		if to_p.length_squared() > 1.0:
			desired_dir = to_p.normalized()
	# Edge avoidance — if too close to a wall, steer back toward center.
	var bias: Vector2 = Vector2.ZERO
	if enemy.position.x < playfield_margin:
		bias.x += 1.0
	elif enemy.position.x > vp.x - playfield_margin:
		bias.x -= 1.0
	if enemy.position.y < playfield_margin:
		bias.y += 1.0
	elif enemy.position.y > vp.y - playfield_margin:
		bias.y -= 1.0
	if bias != Vector2.ZERO:
		desired_dir = (desired_dir * 0.5 + bias.normalized() * 0.5).normalized()

	# Yaw the body toward desired_dir at a turn rate that scales with speed.
	var speed_norm: float = clamp((_speed - min_speed) / max(0.01, max_speed - min_speed), 0.0, 1.0)
	var rate_now: float = lerp(turn_rate_at_min, turn_rate_at_min * turn_speed_falloff, speed_norm)
	if enemy is Node2D:
		# Sprite faces +Y when rotation=0 — same math as inertial_thrust.
		var target_angle: float = desired_dir.angle() + PI * 0.5
		# Sinusoidal weave applied on top of the heading.
		target_angle += deg_to_rad(weave_amplitude_deg) * sin(_t * weave_freq * 2.0 * PI)
		var current: float = enemy.rotation
		var diff: float = wrapf(target_angle - current, -PI, PI)
		var max_step: float = deg_to_rad(rate_now) * delta
		if abs(diff) <= max_step:
			enemy.rotation = target_angle
		else:
			enemy.rotation += sign(diff) * max_step
		if "auto_rotate" in enemy:
			enemy.auto_rotate = false

	# Step along current facing.
	var rot: float = enemy.rotation - PI * 0.5
	var forward: Vector2 = Vector2(cos(rot), sin(rot))
	return forward * _speed * delta


func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
