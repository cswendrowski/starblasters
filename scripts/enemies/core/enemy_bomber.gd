extends EnemyBase
class_name EnemyBomber

# Bomber — large, tough rear-gunner. Roman 2026-06-01 rework.
#
# Arrives in wings of 2–3 and descends slowly from the top, facing UP (rear
# toward the player) so it reads as the player closing in from behind. It
# settles into an upper band and HOLDS there until destroyed, raking the
# pursuing player with a tail turret over a wide rear arc. Worth extra bounty.
#
# (This is the new roster bomber. The original V-formation "bomber wing" unit
# lives on as enemy_bomber_wing.gd, preserved for that event's planned
# overhaul — see that file's header.)
#
# Bespoke (extends EnemyBase) because of the held-position locomotion + the
# arc-gated tail turret + the twin engine contrails; the roster entry sets
# movement/shoot null and the director skips both overrides.
#
# Markers (scene): TailMuzzle (0,27) rear turret; EngineL (-4,29) / EngineR
# (4,29) exhaust nozzles. Faces up, so "rear" is +Y (down, toward the player).

const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")

enum BState { ENTER, HOLD }

# --- Locomotion ----------------------------------------------------------
const ENTER_SPEED := 40.0     # px/s — slow descent into position
const HOLD_Y_MIN  := 70.0     # settle band (upper screen, ahead of player)
const HOLD_Y_MAX  := 108.0
const SWAY_AMPL_X  := 7.0      # gentle drift so the contrails stay alive
const SWAY_AMPL_Y  := 4.0
const SWAY_PERIOD  := 6.0

# --- Tail turret ---------------------------------------------------------
const REAR_ARC_DEG    := 160.0          # full cone, centred on +Y (rear)
const FIRE_INTERVAL_MIN := 0.55
const FIRE_INTERVAL_MAX := 0.85
const TURRET_BULLET_SPEED := 190.0      # small, steady shots

# --- Engine exhaust plumes -----------------------------------------------
# The bomber faces UP with its engines at the rear (bottom), so a position-
# history contrail would stream up UNDER its own long hull and never show.
# Instead each nozzle emits a persistent tapered plume straight DOWN (the
# exhaust direction, toward the chasing player) — same soft focus-trail look,
# recoloured yellow, with a little length flicker so it reads as live thrust.
const PLUME_LEN := 17.0
const PLUME_WIDTH := 3.0
const TRAIL_COLOR := Color(1.0, 0.88, 0.25, 0.9)  # yellow (player trail, recoloured)

var _state: int = BState.ENTER
var _hold_y: float = 90.0
var _sway_t: float = 0.0
var _sway_seed: float = 0.0
var _fire_t: float = 0.0

# One plume Line2D per engine marker.
var _trails: Array[Line2D] = []
const _ENGINE_MARKERS := ["EngineL", "EngineR"]


func _ready() -> void:
	# Large, tough, extra bounty. Overridden on spawn by compose_stats
	# (hp_override / bounty_override) — kept here for manual placement.
	max_health = 30
	bounty_value = 120
	# Faces up (rear/engines toward the pursuing player below); no auto-rotate.
	auto_rotate = false
	# Remains until destroyed — never auto-despawns off an edge.
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_hold_y = randf_range(HOLD_Y_MIN, HOLD_Y_MAX)
	_sway_seed = randf() * TAU
	_fire_t = randf_range(FIRE_INTERVAL_MIN, FIRE_INTERVAL_MAX)
	_build_engine_trails()


func start(pos: Vector2) -> void:
	# Enter from above the director's spawn x so the descent is visible.
	position = Vector2(pos.x, min(pos.y, -20.0))


func _build_engine_trails() -> void:
	var parent := get_parent()
	if parent == null:
		return
	# Width taper: fat at the nozzle, pinched to a point at the tail (flame look).
	var wcurve := Curve.new()
	wcurve.add_point(Vector2(0.0, 1.0))
	wcurve.add_point(Vector2(1.0, 0.0))
	for m in _ENGINE_MARKERS:
		var line := Line2D.new()
		line.width = PLUME_WIDTH
		line.width_curve = wcurve
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		# top_level → ignore parent transform; feed raw GLOBAL points. No
		# to_local() dependency on what kind of node the parent happens to be.
		line.top_level = true
		line.z_index = 1   # render the plume on top of the hull (Roman 2026-06-01)
		var grad := Gradient.new()
		grad.set_color(0, TRAIL_COLOR)                                              # nozzle: opaque yellow
		grad.set_color(1, Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, 0.0))  # tail: transparent
		line.gradient = grad
		parent.add_child(line)
		_trails.append(line)


func _process(delta: float) -> void:
	if _dying:
		return
	_sway_t += delta
	match _state:
		BState.ENTER:
			position.y += ENTER_SPEED * delta
			if position.y >= _hold_y:
				position.y = _hold_y
				_state = BState.HOLD
		BState.HOLD:
			var t: float = _sway_t + _sway_seed
			position.x += SWAY_AMPL_X * cos(t * TAU / SWAY_PERIOD) * delta
			position.y = _hold_y + SWAY_AMPL_Y * sin(t * TAU / SWAY_PERIOD * 1.3)
	_update_engine_trails()
	_update_tail_turret(delta)
	super._process(delta)


# Player-focus-trail style: a world-space Line2D fed the engine marker's
# position history, recoloured yellow. Collapses to a point if perfectly still,
# so the gentle hold-sway keeps the contrails alive.
func _update_engine_trails() -> void:
	for i in _ENGINE_MARKERS.size():
		if i >= _trails.size():
			break
		var line: Line2D = _trails[i]
		if line == null or not is_instance_valid(line):
			continue
		var marker := get_node_or_null(_ENGINE_MARKERS[i]) as Marker2D
		if marker == null:
			continue
		# Persistent downward plume from the nozzle, with a little length flicker
		# so the thrust reads as alive. top_level → points are global.
		var nozzle: Vector2 = marker.global_position
		var len_px: float = PLUME_LEN * randf_range(0.78, 1.0)
		line.points = PackedVector2Array([nozzle, nozzle + Vector2(0.0, len_px)])


# Tail turret: aim at the player and fire a small bullet, but only while the
# player sits inside the 160° rear cone (centred on +Y). Steady cadence.
func _update_tail_turret(delta: float) -> void:
	var player := find_player()
	if player == null:
		return
	var muzzle := get_node_or_null("TailMuzzle") as Marker2D
	var spawn_pos: Vector2 = muzzle.global_position if muzzle else global_position
	var to_player: Vector2 = player.global_position - spawn_pos
	if to_player.length_squared() < 1.0:
		return
	var dir: Vector2 = to_player.normalized()
	# Off-axis angle from straight-down (the rear). Outside the cone → hold fire.
	var off_rear: float = absf(Vector2.DOWN.angle_to(dir))
	if off_rear > deg_to_rad(REAR_ARC_DEG * 0.5):
		return
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	_fire_t = randf_range(FIRE_INTERVAL_MIN, FIRE_INTERVAL_MAX)
	var b = BULLET_SCENE.instantiate()
	b.speed = TURRET_BULLET_SPEED
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(spawn_pos, dir)
	elif "velocity_dir" in b:
		b.velocity_dir = dir
	MuzzleFx.play_enemy(spawn_pos, dir, get_tree().root)
	EnemySfxC.play_for(self)


# Free the world-parented contrails when we die (they outlive the hull node).
func explode() -> void:
	_free_trails()
	super.explode()


func _free_trails() -> void:
	for line in _trails:
		if line != null and is_instance_valid(line):
			line.queue_free()
	_trails.clear()


func _exit_tree() -> void:
	_free_trails()
