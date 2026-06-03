extends "res://scripts/enemies/movement_pattern.gd"

# Hunter Drone: enter from the top of the playfield, descend to commit_y,
# then beeline toward the player. Without the enter phase the drone would
# track the player from off-screen and could overshoot upward.

# 320×400 res rework: halved.
@export var max_speed: float = 180.0
@export var accel: float = 360.0
@export var enter_speed: float = 128.0
@export var commit_y: float = 48.0  # start hunting once we're this far down

enum Phase { ENTER, HUNT }
var _phase: int = Phase.ENTER
var _vel: Vector2 = Vector2.ZERO


func on_start(_enemy) -> void:
	_phase = Phase.ENTER
	_vel = Vector2(0, enter_speed)


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTER:
			var step: Vector2 = _vel * delta
			if enemy.position.y + step.y >= commit_y:
				_phase = Phase.HUNT
			return step
		Phase.HUNT:
			var p: Node = _find_player(enemy)
			var dir: Vector2 = Vector2(0, 1)
			if p:
				dir = (p.global_position - enemy.global_position).normalized()
			_vel = _vel.move_toward(dir * max_speed, accel * delta)
			return _vel * delta
	return Vector2.ZERO


func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
