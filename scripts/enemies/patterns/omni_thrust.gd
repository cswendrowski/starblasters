extends "res://scripts/enemies/movement_pattern.gd"

# Omnidirectional thrust. Translates freely in any direction, decoupled
# from facing. Strafes laterally to dodge while keeping the nose pointed
# at the player. Reads like a hover-tank / interceptor with vector thrust.
#
# Tactic loop:
#   - Hold a stand-off range from the player (target_range).
#   - Pick a strafe direction; flip every strafe_period seconds OR when
#     wall is close, so the enemy weaves left/right instead of running
#     into the playfield edge.
#   - Face the player every frame (enemy.rotation overridden here).

@export var max_speed: float = 160.0
@export var accel: float = 540.0
# Harassment tuning (Roman 2026-05-18 "more player harassment"): closer
# stand-off range, faster juke flips, slightly punchier strafe.
@export var target_range: float = 130.0      # stand-off distance from player
@export var range_tolerance: float = 20.0
@export var strafe_speed: float = 135.0
@export var strafe_period_min: float = 0.45
@export var strafe_period_max: float = 1.1
@export var face_player: bool = true
# Half-width of the playfield band where the enemy will refuse to strafe
# further (auto-reverses). 320×400 default keeps a 24-px wall margin.
@export var playfield_margin: float = 24.0

var _vel: Vector2 = Vector2.ZERO
var _strafe_dir: int = 1
var _strafe_t: float = 0.0
var _strafe_period: float = 1.0


func on_start(_enemy) -> void:
	_vel = Vector2.ZERO
	_strafe_dir = 1 if (randf() < 0.5) else -1
	_strafe_t = 0.0
	_strafe_period = randf_range(strafe_period_min, strafe_period_max)


func compute_step(enemy, delta: float) -> Vector2:
	var player := _find_player(enemy)
	# Flip strafe direction periodically.
	_strafe_t += delta
	if _strafe_t >= _strafe_period:
		_strafe_t = 0.0
		_strafe_dir = -_strafe_dir
		_strafe_period = randf_range(strafe_period_min, strafe_period_max)

	# Bounce off the playfield walls so a strafe doesn't push us out.
	# Wider lookahead margin so the strafe flip happens before we corner
	# (Roman, 2026-05-17: "they are bumping into the edges and getting
	# caught in corners"). Horizontal walls = 216-wide playfield band;
	# vertical walls = full viewport height.
	var vp: Vector2 = enemy.get_viewport_rect().size
	var x_lo: float = Playfield.X_MIN
	var x_hi: float = Playfield.X_MAX
	var lookahead: float = 22.0
	if enemy.position.x < x_lo + playfield_margin + lookahead and _strafe_dir < 0:
		_strafe_dir = 1
		_strafe_t = 0.0
	elif enemy.position.x > x_hi - playfield_margin - lookahead and _strafe_dir > 0:
		_strafe_dir = -1
		_strafe_t = 0.0

	# Desired velocity: radial component holds stand-off range, tangent
	# component is the lateral strafe. Edge-avoidance bias added as a
	# steering term so we don't bump into corners.
	var desired_vel := Vector2.ZERO
	if player:
		var to_p: Vector2 = player.global_position - enemy.global_position
		var dist: float = to_p.length()
		if dist > 0.01:
			var dir: Vector2 = to_p / dist
			# Radial: positive = approach, negative = back off.
			var radial: float = 0.0
			if dist > target_range + range_tolerance:
				radial = max_speed
			elif dist < target_range - range_tolerance:
				radial = -max_speed * 0.6
			# Tangent: perpendicular to dir.
			var tangent: Vector2 = Vector2(-dir.y, dir.x) * float(_strafe_dir) * strafe_speed
			desired_vel = dir * radial + tangent
	# Edge avoidance — Roman, 2026-05-17 Movement Lab v2: "Omni seems
	# like it's magnetized to the walls now, check that wall avoidance
	# is working right."
	# Two-stage approach:
	#   1. If we're inside the inner band, blend the desired velocity with
	#      a push-away direction. The closer to the wall, the more the
	#      push dominates (smoothstep), so we don't fight the strafe term
	#      when we're well clear.
	#   2. After move_toward, zero out any velocity component still aimed
	#      INTO the wall, so we slide along walls instead of pinning.
	var avoid_band: float = playfield_margin + 16.0
	var push_dir: Vector2 = Vector2.ZERO
	if enemy.position.x < x_lo + avoid_band:
		push_dir.x += 1.0
	elif enemy.position.x > x_hi - avoid_band:
		push_dir.x -= 1.0
	if enemy.position.y < avoid_band:
		push_dir.y += 1.0
	elif enemy.position.y > vp.y - avoid_band:
		push_dir.y -= 1.0
	if push_dir != Vector2.ZERO:
		# Blend factor: 0 at avoid_band, 1 at the wall.
		var dx: float = min(
			abs(enemy.position.x - x_lo) if push_dir.x > 0 else (x_hi - enemy.position.x) if push_dir.x < 0 else avoid_band,
			avoid_band
		)
		var dy: float = min(
			abs(enemy.position.y - 0.0) if push_dir.y > 0 else (vp.y - enemy.position.y) if push_dir.y < 0 else avoid_band,
			avoid_band
		)
		var nearest: float = min(dx if push_dir.x != 0 else avoid_band, dy if push_dir.y != 0 else avoid_band)
		var blend: float = clamp(1.0 - (nearest / avoid_band), 0.0, 1.0)
		desired_vel = desired_vel.lerp(push_dir.normalized() * max_speed, blend)

	_vel = _vel.move_toward(desired_vel, accel * delta)

	# Zero velocity component into walls so we slide along, not pin.
	if enemy.position.x <= x_lo + playfield_margin and _vel.x < 0.0:
		_vel.x = 0.0
	elif enemy.position.x >= x_hi - playfield_margin and _vel.x > 0.0:
		_vel.x = 0.0
	if enemy.position.y <= playfield_margin and _vel.y < 0.0:
		_vel.y = 0.0
	elif enemy.position.y >= vp.y - playfield_margin and _vel.y > 0.0:
		_vel.y = 0.0

	# Face the player. (Sprite is authored facing up, so +PI/2 brings the
	# nose to the +Y axis and rotation tracks the direction-to-player.)
	if face_player and player and enemy is Node2D:
		var look: Vector2 = player.global_position - enemy.global_position
		if look.length_squared() > 1.0:
			enemy.rotation = look.angle() + PI * 0.5
			# Suppress enemy_core's auto-rotate so it doesn't fight us.
			if "auto_rotate" in enemy:
				enemy.auto_rotate = false

	return _vel * delta


func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
