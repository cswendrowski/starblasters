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

@export var max_speed: float = 120.0
@export var accel: float = 540.0
# Harassment tuning (Roman 2026-05-18 "more player harassment"): closer
# stand-off range, faster juke flips, slightly punchier strafe.
@export var target_range: float = 130.0      # stand-off distance from player
@export var range_tolerance: float = 20.0
@export var strafe_speed: float = 108.0
@export var strafe_period_min: float = 0.45
@export var strafe_period_max: float = 1.1
@export var face_player: bool = true
# Half-width of the playfield band where the enemy will refuse to strafe
# further (auto-reverses). 320×400 default keeps a 24-px wall margin.
@export var playfield_margin: float = 24.0
# PERSISTENCE (Roman 2026-06-10): how long the harasser hangs around attacking before it disengages
# and dives out the bottom. -1 = never leave (chase/attack forever, the old behaviour). Otherwise a
# duration in SECONDS; on expiry the bottom no-fly clamp is dropped and it accelerates straight down.
@export var persistence: float = -1.0
# Pass budget (Roman 2026-06-11): leave for good after this many passes (failed attack
# runs that ended in a bottom exit + recycle). -1 = unlimited (only `persistence` time
# governs). Counted on the ENEMY (survives the per-pass on_start reset).
@export var max_passes: int = -1
# Base turn rate (rad/s) toward the player, DIVIDED by the unit's size-weight so big ships turn
# laggier and can't hold a perfect lock (Roman 2026-06-10). The old code snapped rotation instantly.
@export var turn_rate: float = 5.0

var _vel: Vector2 = Vector2.ZERO
var _strafe_dir: int = 1
var _strafe_t: float = 0.0
var _strafe_period: float = 1.0
var _alive_t: float = 0.0   # seconds since spawn (persistence clock)
var _leaving: bool = false


func on_start(enemy) -> void:
	_vel = Vector2.ZERO
	_strafe_dir = 1 if (randf() < 0.5) else -1
	_strafe_t = 0.0
	_strafe_period = randf_range(strafe_period_min, strafe_period_max)
	_alive_t = 0.0
	_leaving = false
	# Pass budget: on_start re-runs on every recycle, so count passes on the ENEMY.
	# Past the budget, disengage AND stop recycling so this re-entry leaves for good.
	if max_passes >= 0 and enemy != null:
		var passes: int = int(enemy.get_meta("_omni_passes", 0)) + 1
		enemy.set_meta("_omni_passes", passes)
		if passes > max_passes:
			_leaving = true
			if "recycle_passes" in enemy:
				enemy.recycle_passes = 0   # don't fly back — dive out and free


# Size-weight from the enemy's display_scale (clamped so small chaff isn't hyper-twitchy). Bigger
# ship => more inertia: laggier turn + slower acceleration.
func _weight(enemy) -> float:
	var w: float = 1.0
	if "display_scale" in enemy:
		w = float(enemy.display_scale)
	return maxf(0.6, w)


func compute_step(enemy, delta: float) -> Vector2:
	# Persistence: once the harasser has attacked long enough, disengage and dive out the bottom
	# (past the no-fly line, so the host's offscreen path recycles/frees it). -1 = never leave.
	_alive_t += delta
	if not _leaving and persistence >= 0.0 and _alive_t >= persistence:
		_leaving = true
	if _leaving:
		var accel_exit: float = accel / _weight(enemy)
		_vel = _vel.move_toward(Vector2(0.0, max_speed), accel_exit * delta)
		if "auto_rotate" in enemy:
			enemy.auto_rotate = true   # let it point along its dive as it leaves
		return _vel * delta

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
	# Bottom bound = the no-fly line (engagement band's departure edge), NOT the screen edge — so the
	# Omni harasser stays in the firing zone and never sinks into the dead space below the player where
	# it can't be shot (Roman 2026-06-10). It exits via the normal recycle/offscreen path, not by diving.
	var no_fly_y: float = Zones.DEPARTURE_START
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
	elif enemy.position.y > no_fly_y - avoid_band:
		push_dir.y -= 1.0
	if push_dir != Vector2.ZERO:
		# Blend factor: 0 at avoid_band, 1 at the wall.
		var dx: float = min(
			abs(enemy.position.x - x_lo) if push_dir.x > 0 else (x_hi - enemy.position.x) if push_dir.x < 0 else avoid_band,
			avoid_band
		)
		var dy: float = min(
			abs(enemy.position.y - 0.0) if push_dir.y > 0 else (no_fly_y - enemy.position.y) if push_dir.y < 0 else avoid_band,
			avoid_band
		)
		var nearest: float = min(dx if push_dir.x != 0 else avoid_band, dy if push_dir.y != 0 else avoid_band)
		var blend: float = clamp(1.0 - (nearest / avoid_band), 0.0, 1.0)
		desired_vel = desired_vel.lerp(push_dir.normalized() * max_speed, blend)

	# Size-weighted acceleration = movement inertia (heavier ships change velocity slower).
	_vel = _vel.move_toward(desired_vel, (accel / _weight(enemy)) * delta)

	# Zero velocity component into walls so we slide along, not pin.
	if enemy.position.x <= x_lo + playfield_margin and _vel.x < 0.0:
		_vel.x = 0.0
	elif enemy.position.x >= x_hi - playfield_margin and _vel.x > 0.0:
		_vel.x = 0.0
	if enemy.position.y <= playfield_margin and _vel.y < 0.0:
		_vel.y = 0.0
	elif enemy.position.y >= no_fly_y and _vel.y > 0.0:
		_vel.y = 0.0

	# Face the player, but RATE-LIMITED by the unit's weight so it can't hold a perfect lock — a big
	# ship lags behind a juking player (Roman 2026-06-10). (Sprite is authored facing up, so +PI/2
	# brings the nose to the +Y axis.) The old code snapped rotation exactly every frame.
	if face_player and player and enemy is Node2D:
		var look: Vector2 = player.global_position - enemy.global_position
		if look.length_squared() > 1.0:
			var target_rot: float = look.angle() + PI * 0.5
			var rate: float = turn_rate / _weight(enemy)
			enemy.rotation = rotate_toward(enemy.rotation, target_rot, rate * delta)
			# Suppress enemy_core's auto-rotate so it doesn't fight us.
			if "auto_rotate" in enemy:
				enemy.auto_rotate = false

	return _vel * delta


func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
