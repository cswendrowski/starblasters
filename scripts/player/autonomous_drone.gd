extends Node2D
class_name AutonomousDrone

# Drone Swarm super drone. Cobalt 2026-05-21: tethered to the player
# (≤ TETHER_RADIUS px from ship center, constrained to the playfield
# band) and free to maneuver in that area while it targets enemies.
# Fires a basic blaster cannon at the chosen target. Targeting rule:
# bosses first, otherwise the enemy nearest the player.
#
# Lifetime is owned by the spawner (drone_swarm.gd); the drone frees
# itself only when the parent ship goes away.

const BULLET_SCENE = preload("res://scenes/projectiles/bullet.tscn")

const TETHER_RADIUS := 20.0
const MOVE_SPEED := 140.0
const FIRE_INTERVAL := 0.22
const BULLET_DAMAGE := 1

var _player: Node2D = null
var _cooldown: float = 0.0
# Per-drone wobble so a swarm doesn't all stack on the same target
# offset. Initialized via bind_player().
var _angle_seed: float = 0.0
var _drift_phase: float = 0.0


func _ready() -> void:
	_drift_phase = randf() * TAU


func bind_player(player: Node2D, angle_seed: float) -> void:
	_player = player
	_angle_seed = angle_seed


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_cooldown -= delta
	_drift_phase += delta * 2.5
	# Pick a target inside the playfield. Bosses preempt closest.
	var target: Node = _pick_target()
	# Movement: drift toward target X (if any) within tether radius, else
	# orbit player. Use sine to wobble in/out so multiple drones in a
	# swarm don't all converge on the same spot.
	var anchor: Vector2 = _player.global_position
	var desired: Vector2 = anchor + Vector2(
		cos(_angle_seed + _drift_phase) * TETHER_RADIUS * 0.85,
		sin(_angle_seed + _drift_phase * 0.7) * TETHER_RADIUS * 0.6 - 6.0,
	)
	if target and is_instance_valid(target):
		# Bias toward target's X within the tether band.
		var dx: float = clampf(target.global_position.x - anchor.x, -TETHER_RADIUS, TETHER_RADIUS)
		desired = anchor + Vector2(dx, -TETHER_RADIUS * 0.8 + sin(_drift_phase) * 4.0)
	var to_desired: Vector2 = desired - global_position
	var step: float = MOVE_SPEED * delta
	if to_desired.length() > step:
		position += to_desired.normalized() * step
	else:
		position = desired
	# Constrain to the playfield band so drones don't drift into the
	# side gutters.
	if Playfield:
		position.x = clamp(position.x, Playfield.X_MIN + 4.0, Playfield.X_MAX - 4.0)
		position.y = clamp(position.y, Playfield.Y_MIN + 4.0, Playfield.Y_MAX - 4.0)
	# Fire at the chosen target. If no target, hold fire.
	if target and is_instance_valid(target) and _cooldown <= 0.0:
		_cooldown = FIRE_INTERVAL
		_fire_at(target)


func _pick_target() -> Node:
	if _player == null:
		return null
	var tree := get_tree()
	if tree == null:
		return null
	# Bosses first — scene_file_path contains "boss".
	for n in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		var path: String = n.scene_file_path if "scene_file_path" in n else ""
		if path.find("boss") != -1:
			return n
	# Otherwise pick the enemy closest to the player.
	var best: Node = null
	var best_d: float = INF
	var anchor: Vector2 = _player.global_position
	for n in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		var d: float = (n.global_position - anchor).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best


func _fire_at(target: Node) -> void:
	if BULLET_SCENE == null:
		return
	var bullet = BULLET_SCENE.instantiate()
	get_tree().root.add_child(bullet)
	if "damage" in bullet:
		bullet.damage = BULLET_DAMAGE
	var dir: Vector2 = Vector2(0, -1)
	if target and is_instance_valid(target) and target is Node2D:
		dir = ((target as Node2D).global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, -1)
	if bullet.has_method("start"):
		bullet.start(global_position + Vector2(0, -4), dir)
	# Tiny audio for shoot — reuse the player's basic blaster SFX if
	# available; otherwise silent.
