extends Area2D
class_name AutonomousDrone

# Combat Drone (Roman 2026-07-08 rebuild — scrapped the old orbit/intercept drone). A companion that
# flanks the player and fires a mark-scaled blaster at the nearest threat for a fixed 30s, then
# disintegrates blue.
#   - Spawns UNDER the player (its position now), then after a per-drone stagger delay pops in and
#     slides LEFT/RIGHT to flank the player with an 8px gap (player half 7 + 8 + drone half 5 = 20 center).
#   - Same-side drones stack outward 4px apart (5 + 4 + 5 = 14 center-to-center).
#   - Follows the player with slight inertia (a damped spring toward its flank slot).
#   - Fires bullet_blaster at the nearest "enemies"-group node (enemy ships AND incoming rockets/missiles,
#     which are in that group), turning to face it. Damage = the effective blaster mark (2/mark).
#   - Self-owned 30s lifetime → a blue disintegrate (flash blue, fade + shrink). No collision / no HP.
#
# Lifetime is DRONE-owned now (was player deploy-timer owned): each drone self-expires, so waves overlap
# and the player just spawns + counts ammo (player._tick_deploy). begin_shutdown() (player death / unequip)
# routes into the same blue disintegrate.

const BULLET_SCENE = preload("res://scenes/projectiles/bullet_blaster.tscn")
const Playfield = preload("res://scripts/systems/playfield.gd")

const LIFETIME := 30.0
const FIRE_INTERVAL := 0.22
const FOLLOW_SPRING := 30.0       # damped-spring stiffness toward the flank slot (slight inertia)
const FOLLOW_DAMP := 9.0
const MAX_SPEED := 300.0
const BASE_GAP := 20.0            # player-center → innermost drone-center (8px edge gap)
const SLOT_SPACING := 14.0        # same-side center-to-center (4px edge gap)
const UNDER_OFFSET := 8.0         # spawns this far below the player before flanking
const BLASTER_BASE_DMG := 2       # Mk1 Energy Blaster damage (blaster is 2/mark)

const DISINTEGRATE_TIME := 0.4
const DISINTEGRATE_BLUE := Color(0.35, 0.62, 1.0, 1.0)

var _player: Node2D = null
var _slot: int = 0
var _spawn_delay: float = 0.0
var _blaster_mark: int = 1
var _vel: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _life: float = LIFETIME
var _active: bool = false          # false while waiting out the stagger delay (hidden, riding under player)
var _bound: bool = false           # set once bind() runs — before that, a null player just waits (not death)
var _dying: bool = false
var _dis_t: float = 0.0


func _ready() -> void:
	# Timed combat drone — no collision/interception (that was the old shield drone).
	monitoring = false
	monitorable = false


# Called (deferred) by the Combat Drones Part on deploy.
func bind(player: Node2D, slot: int, spawn_delay: float, blaster_mark: int) -> void:
	_player = player
	_bound = true
	_slot = slot
	_spawn_delay = maxf(0.0, spawn_delay)
	_blaster_mark = maxi(1, blaster_mark)
	if player != null and is_instance_valid(player):
		global_position = player.global_position + Vector2(0, UNDER_OFFSET)
	visible = false


func _process(delta: float) -> void:
	if _dying:
		_tick_disintegrate(delta)
		return
	if _player == null or not is_instance_valid(_player):
		if _bound:
			_begin_disintegrate()   # player gone AFTER binding → fade out (else just wait for bind)
		return
	# Stagger: hold UNDER the player (hidden) until this drone's delay elapses, then pop in.
	if not _active:
		_spawn_delay -= delta
		global_position = _player.global_position + Vector2(0, UNDER_OFFSET)
		if _spawn_delay <= 0.0:
			_active = true
			visible = true
		return
	# Lifetime → blue disintegrate.
	_life -= delta
	if _life <= 0.0:
		_begin_disintegrate()
		return
	# Follow the flank slot with slight inertia (damped spring).
	var to_desired: Vector2 = _flank_pos() - global_position
	_vel += (to_desired * FOLLOW_SPRING - _vel * FOLLOW_DAMP) * delta
	if _vel.length() > MAX_SPEED:
		_vel = _vel.normalized() * MAX_SPEED
	global_position += _vel * delta
	global_position.x = clampf(global_position.x, Playfield.X_MIN + 4.0, Playfield.X_MAX - 4.0)
	global_position.y = clampf(global_position.y, Playfield.Y_MIN + 4.0, Playfield.Y_MAX - 4.0)
	# Turn + fire at the nearest threat.
	_cooldown -= delta
	var target: Node2D = _nearest_threat()
	if target != null:
		var aim: Vector2 = target.global_position - global_position
		if aim.length_squared() > 0.01:
			rotation = aim.angle() + PI * 0.5   # up-pointing sprite → face the target
			if _cooldown <= 0.0:
				_cooldown = FIRE_INTERVAL
				_fire_at(target)
	else:
		rotation = lerp_angle(rotation, 0.0, clampf(6.0 * delta, 0.0, 1.0))   # ease back upright when idle


# Slot i: even → RIGHT, odd → LEFT; rank = i/2 stacks outward. Innermost = 8px gap; 4px between drones.
func _flank_pos() -> Vector2:
	var side: float = 1.0 if (_slot % 2 == 0) else -1.0
	var rank: int = _slot / 2
	return _player.global_position + Vector2(side * (BASE_GAP + float(rank) * SLOT_SPACING), 0.0)


# Nearest node in the "enemies" group (enemy ships + incoming rockets/missiles, which join it). Skips
# nothing by HP so rockets/missiles are valid targets, per the brief.
func _nearest_threat() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for n in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = (n.global_position - global_position).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best


func _fire_at(target: Node2D) -> void:
	if BULLET_SCENE == null or target == null:
		return
	var b = BULLET_SCENE.instantiate()
	get_tree().root.add_child(b)
	if "damage" in b:
		b.damage = BLASTER_BASE_DMG * _blaster_mark   # effective blaster mark (Mk1 blaster = 2)
	var dir: Vector2 = target.global_position - global_position
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector2(0, -1)
	if b.has_method("start"):
		b.start(global_position + dir * 5.0, dir)


# --- Blue disintegrate (lifetime expiry / player gone / shutdown) ---
func _begin_disintegrate() -> void:
	if _dying:
		return
	_dying = true
	_dis_t = 0.0
	visible = true
	monitoring = false
	monitorable = false


func _tick_disintegrate(delta: float) -> void:
	_dis_t += delta
	var f: float = clampf(_dis_t / DISINTEGRATE_TIME, 0.0, 1.0)
	# Flash blue, fade out, shrink away.
	modulate = Color(DISINTEGRATE_BLUE.r, DISINTEGRATE_BLUE.g, DISINTEGRATE_BLUE.b, 1.0 - f)
	scale = Vector2.ONE.lerp(Vector2(0.15, 0.15), f)
	if f >= 1.0:
		queue_free()


# Player death / unequip cleanup — route through the same blue disintegrate.
func begin_shutdown() -> void:
	_begin_disintegrate()
