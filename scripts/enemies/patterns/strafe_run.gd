extends "res://scripts/enemies/movement_pattern.gd"

# Strafe Run (Roman 2026-06-08, ported from the bespoke enemy_strafer): a capped-turn strafing
# pass. Steer toward a point BESIDE the player (never at it, so it flies past), then break off
# toward a bottom-corner exit. The host keeps auto_rotate=true so the nose tracks the flight
# heading; pair with a FORWARD-aim weapon + fire_only_on_target so it strafes the player as the
# nose sweeps across. allow_side_exit is set so it can leave out a side/bottom.
#
# One pass per spawn; let enemy_core recycle_passes drive repeat runs if wanted.

const Playfield = preload("res://scripts/playfield.gd")

@export var travel_speed: float = 240.0
@export var turn_rate_deg: float = 160.0
@export var strafe_offset: float = 50.0      # how far beside the player to aim the pass
@export var approach_timeout: float = 1.6    # force the break-off after this long

enum Ph { SEEK, BREAK }
var _ph: int = Ph.SEEK
var _t: float = 0.0
var _side: float = 1.0
var _vel: Vector2 = Vector2(0, 1)
var _exit_x: float = 0.0


func on_start(enemy) -> void:
	enemy.allow_side_exit = true
	_ph = Ph.SEEK
	_t = 0.0
	# Strafe across toward the roomier side; pass on that side of the player.
	_side = 1.0 if enemy.position.x < Playfield.CENTER.x else -1.0
	_vel = Vector2(_side * 0.5, 1.0).normalized() * travel_speed
	_exit_x = clampf(Playfield.CENTER.x + _side * (Playfield.W * 0.5 + 60.0),
		Playfield.X_MIN - 40.0, Playfield.X_MAX + 40.0)


func compute_step(enemy, delta: float) -> Vector2:
	_t += delta
	var target: Vector2
	if _ph == Ph.SEEK:
		var p = enemy.find_player() if enemy.has_method("find_player") else null
		if p != null and is_instance_valid(p):
			target = p.global_position + Vector2(_side * strafe_offset, 0.0)
			# Break off once we've drawn level/past the player, or the approach times out.
			if enemy.global_position.y >= p.global_position.y or _t >= approach_timeout:
				_ph = Ph.BREAK
		else:
			target = Vector2(_exit_x, Playfield.Y_MAX + 80.0)
	else:
		target = Vector2(_exit_x, Playfield.Y_MAX + 80.0)
	_vel = _steer(_vel, target - enemy.global_position, delta)
	return _vel * delta


# Rotate the current heading toward `desired` by at most turn_rate*dt, keeping speed constant.
func _steer(vel: Vector2, desired: Vector2, dt: float) -> Vector2:
	if desired.length_squared() < 0.0001:
		return vel
	var cur: Vector2 = vel.normalized()
	var want: Vector2 = desired.normalized()
	var max_turn: float = deg_to_rad(turn_rate_deg) * dt
	var turn: float = clampf(cur.angle_to(want), -max_turn, max_turn)
	return cur.rotated(turn) * travel_speed
