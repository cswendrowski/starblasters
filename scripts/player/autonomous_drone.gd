extends Area2D
class_name AutonomousDrone

# Combined Drone Swarm super (Cobalt 2026-05-21): consolidates the old
# secondary Shield Drone + the prior autonomous shooter into one entity.
# Each drone:
#   - Orbits the player (≤ TETHER_RADIUS px), free to maneuver in band
#   - Picks bosses first, otherwise the enemy nearest the player
#   - Fires the basic blaster bullet at the chosen target
#   - INTERCEPTS incoming enemy projectiles with its body — bullets in
#     the "enemy_bullets" group entering the Area2D are eaten and the
#     drone takes one ablative hit
#   - Pops after MAX_HITS contacts (default 2) so they're not invulnerable
#
# Lifetime is owned by player._tick_deploy: it counts the deploy duration
# down and calls begin_shutdown() on each surviving drone when it expires
# (Roman 2026-05-30 — Combat Drones converted from a super to a deploy
# secondary; the old drone_swarm.gd cleanup timer was replaced).

const BULLET_SCENE = preload("res://scenes/projectiles/bullet.tscn")

const TETHER_RADIUS := 20.0
const MOVE_SPEED := 140.0
const FIRE_INTERVAL := 0.22
const BULLET_DAMAGE := 1
const MAX_HITS := 2
# Boids-style separation so a 4-6 drone swarm doesn't stack into a single
# pixel near the desired anchor (Roman, 2026-05-23). Only repels OTHER
# super-drones; the player + target attraction stays untouched.
const SEPARATION_RADIUS := 32.0
const SEPARATION_STRENGTH := 120.0
const SUPER_DRONE_GROUP := "super_drone"

var _player: Node2D = null
var _cooldown: float = 0.0
var _angle_seed: float = 0.0
var _drift_phase: float = 0.0
var _hits: int = 0
var _dying: bool = false
# Shutdown animation (duration-expiry). When begin_shutdown() is called by
# the deploy owner (player._end_deploy), the drone stops fighting, darkens to
# ~50% brightness, and falls toward the bottom of the screen, free-ing once
# it's off the bottom edge — reads as the drone powering down + dropping away.
# Distinct from _explode() (early MAX_HITS death), which is a silent free.
var _shutting_down: bool = false
var _fall_velocity: float = 0.0
const SHUTDOWN_DARKEN := Color(0.5, 0.5, 0.5, 1.0)
const SHUTDOWN_DARKEN_RATE := 6.0    # modulate lerp speed toward 50% brightness
const SHUTDOWN_GRAVITY := 280.0      # downward accel (px/s^2)
const SHUTDOWN_MAX_FALL := 240.0     # terminal fall speed (px/s)
const SHUTDOWN_OFFSCREEN_MARGIN := 24.0


func _ready() -> void:
	_drift_phase = randf() * TAU
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	# Self-register so peer drones can find us for separation.
	if not is_in_group(SUPER_DRONE_GROUP):
		add_to_group(SUPER_DRONE_GROUP)


func bind_player(player: Node2D, angle_seed: float) -> void:
	_player = player
	_angle_seed = angle_seed


func _process(delta: float) -> void:
	if _dying:
		return
	# Shutdown takes priority over everything: it must run even if the player
	# is gone, and must NOT be clamped to the playfield (the drone falls off
	# the bottom). Read the viewport for the despawn edge per CLAUDE.md.
	if _shutting_down:
		modulate = modulate.lerp(SHUTDOWN_DARKEN, clampf(SHUTDOWN_DARKEN_RATE * delta, 0.0, 1.0))
		_fall_velocity = min(_fall_velocity + SHUTDOWN_GRAVITY * delta, SHUTDOWN_MAX_FALL)
		position.y += _fall_velocity * delta
		var bottom: float = 270.0
		var vp := get_viewport()
		if vp != null:
			bottom = vp.get_visible_rect().size.y
		if position.y > bottom + SHUTDOWN_OFFSCREEN_MARGIN:
			queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_cooldown -= delta
	_drift_phase += delta * 2.5
	var target: Node = _pick_target()
	var anchor: Vector2 = _player.global_position
	var desired: Vector2 = anchor + Vector2(
		cos(_angle_seed + _drift_phase) * TETHER_RADIUS * 0.85,
		sin(_angle_seed + _drift_phase * 0.7) * TETHER_RADIUS * 0.6 - 6.0,
	)
	if target and is_instance_valid(target):
		var dx: float = clampf(target.global_position.x - anchor.x, -TETHER_RADIUS, TETHER_RADIUS)
		desired = anchor + Vector2(dx, -TETHER_RADIUS * 0.8 + sin(_drift_phase) * 4.0)
	# Boids separation — sum of repulsion vectors from peer super-drones
	# within SEPARATION_RADIUS. Closer peers contribute more (1/distance).
	# Added as a velocity (px/s) on top of the seek-to-desired step, then
	# the combined step is capped at MOVE_SPEED so separation never makes
	# a drone outrun the swarm's intended speed.
	var separation: Vector2 = Vector2.ZERO
	for peer in get_tree().get_nodes_in_group(SUPER_DRONE_GROUP):
		if peer == self or not is_instance_valid(peer):
			continue
		var offset: Vector2 = global_position - (peer as Node2D).global_position
		var dist: float = offset.length()
		if dist > 0.0 and dist < SEPARATION_RADIUS:
			separation += offset.normalized() / max(dist, 1.0)
	separation *= SEPARATION_STRENGTH
	var seek_v: Vector2 = (desired - global_position) / max(delta, 0.0001)
	var combined: Vector2 = seek_v + separation
	var max_step: float = MOVE_SPEED * delta
	var step_vec: Vector2 = combined * delta
	if step_vec.length() > max_step:
		step_vec = step_vec.normalized() * max_step
	position += step_vec
	if Playfield:
		position.x = clamp(position.x, Playfield.X_MIN + 4.0, Playfield.X_MAX - 4.0)
		position.y = clamp(position.y, Playfield.Y_MIN + 4.0, Playfield.Y_MAX - 4.0)
	if target and is_instance_valid(target) and _cooldown <= 0.0:
		_cooldown = FIRE_INTERVAL
		_fire_at(target)


# Bullet / enemy contact handler. We absorb enemy bullets (eat them so
# they can't reach the player) and take an ablative hit each time. After
# MAX_HITS the drone pops.
func _on_area_entered(area: Area2D) -> void:
	if _dying:
		return
	if area == null or area == _player:
		return
	if area.is_in_group("player_drones") or area.is_in_group("player"):
		return
	# Anything in "enemies" or "enemy_bullets" counts as an incoming hit.
	# Most enemy projectiles are in the enemies group via EnemyBase, so
	# checking enemies is the broad-stroke catch.
	if not (area.is_in_group("enemies") or area.is_in_group("enemy_bullets")):
		return
	# Eat the projectile if it's a bullet-shaped enemy (low HP, no boss).
	if area.has_method("take_hit") and "max_health" in area and int(area.max_health) <= 1:
		area.queue_free()
	_hits += 1
	if _hits >= MAX_HITS:
		_explode()


func _explode() -> void:
	if _dying:
		return
	_dying = true
	# Drones despawn silently — no explosion VFX (Bug fix 2026-05-26: drones
	# should not spawn explosions when they die or are cleaned up).
	queue_free()


# Begin the powering-down animation: stop fighting, darken to ~50% brightness,
# and fall toward the bottom of the screen, free-ing once off the bottom edge.
# Called by the deploy owner (player._end_deploy) when the duration expires.
# Idempotent + guarded so it never fights an early MAX_HITS death.
func begin_shutdown() -> void:
	if _dying or _shutting_down:
		return
	_shutting_down = true
	_fall_velocity = 0.0
	# Stop intercepting/absorbing — the drone is done.
	monitoring = false
	monitorable = false
	if is_in_group(SUPER_DRONE_GROUP):
		remove_from_group(SUPER_DRONE_GROUP)


func _pick_target() -> Node:
	if _player == null:
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		var path: String = n.scene_file_path if "scene_file_path" in n else ""
		if path.find("boss") != -1:
			return n
	var best: Node = null
	var best_d: float = INF
	var anchor: Vector2 = _player.global_position
	for n in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		# Skip projectiles + chaff that we don't really want to "target".
		if "max_health" in n and int(n.max_health) <= 1:
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
