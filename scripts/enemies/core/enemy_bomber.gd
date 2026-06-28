extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyBomber

# Bomber — large, tough rear-gunner. Roman 2026-06-01; on-lane migration 2026-06-08.
#
# Arrives in wings of 2–3, descends from the top facing UP (rear toward the player), settles
# into an upper band and HOLDS there until destroyed, raking the pursuing player with a tail
# gun over a wide rear arc.
#
# MOVEMENT now on the lane system: the Drift pattern (descend → jiggle-hold) drives motion.
# The tail gun is now a shared EnemyTurret in ARC-GATE mode (holds fire outside its 160° rear
# cone) instead of the hand-rolled cone test. Still bespoke: the twin downward engine contrails.
#
# Markers (scene): TurretTail (0,27) rear turret mount; EngineL (-4,29) / EngineR (4,29) nozzles.
# Faces up, so "rear" is +Y (down, toward the player).

const Drift = preload("res://scripts/enemies/patterns/drift.gd")
const BombingRunAttack = preload("res://scripts/enemies/bombing_run_attack.gd")

# --- Bombing run (overhead carpet bomb) ----------------------------------
# Periodically the bomber transitions out (flies up off the top), becomes an overhead shadow, and
# carpet-bombs a lane pattern (seq_bombing_run), then drops back into its hold. Toggle per-spawn.
@export var bombing_run_enabled: bool = true
const BOMB_RUN_DELAY_MIN := 5.0
const BOMB_RUN_DELAY_MAX := 9.0
var _bomb_cooldown: float = 0.0
var _bomb_seq: Node = null


# --- Engine exhaust plumes -----------------------------------------------
const PLUME_LEN := 17.0
const PLUME_WIDTH := 3.0
const TRAIL_COLOR := Color(1.0, 0.88, 0.25, 0.9)  # yellow (player trail, recoloured)

var _trails: Array[Line2D] = []
const _ENGINE_MARKERS := ["EngineL", "EngineR"]


func _ready() -> void:
	max_health = 30
	bounty_value = 120
	auto_rotate = false                       # faces up; rear/engines toward the player
	offscreen_mode = OffscreenMode.NONE       # holds until destroyed
	# Drift hold in the upper band (the matrix assigns drift_mid; this is the fallback).
	if movement == null:
		var d := Drift.new()
		d.hover_y = 90.0
		movement = d
	super._ready()
	_build_engine_trails()
	_bomb_cooldown = randf_range(BOMB_RUN_DELAY_MIN, BOMB_RUN_DELAY_MAX)


# Enter from above the director's spawn x so the descent into the hold is visible.
func start(pos: Vector2) -> void:
	super.start(Vector2(pos.x, minf(pos.y, -20.0)))


func _process(delta: float) -> void:
	if external_control:
		return                        # bombing-run sequence owns the transform
	super._process(delta)             # Drift pattern + components
	if not _dying:
		_update_engine_trails()
		_tick_bombing_run(delta)


# --- Bombing run trigger -------------------------------------------------
func _tick_bombing_run(delta: float) -> void:
	if not bombing_run_enabled or _bomb_seq != null:
		return
	# Only once settled into the hold band (descended in from the spawn above the top).
	if global_position.y < Zones.ENTRY_END:
		return
	_bomb_cooldown -= delta
	if _bomb_cooldown <= 0.0:
		_launch_bombing_run()


func _launch_bombing_run() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		_bomb_cooldown = randf_range(BOMB_RUN_DELAY_MIN, BOMB_RUN_DELAY_MAX)
		return
	external_control = true
	_set_tail_gun_active(false)
	_clear_engine_trails()
	_bomb_seq = BombingRunAttack.launch(self, spr, {
		"pattern": float(randi() % 4),
		"direction": float(randi() % 2),
	})
	if _bomb_seq == null:
		_end_bombing_run()
		return
	_bomb_seq.finished.connect(_end_bombing_run)


func _end_bombing_run() -> void:
	external_control = false
	_bomb_seq = null
	_bomb_cooldown = randf_range(BOMB_RUN_DELAY_MIN, BOMB_RUN_DELAY_MAX)
	if is_instance_valid(self) and not _dying:
		_set_tail_gun_active(true)


func _set_tail_gun_active(on: bool) -> void:
	# The tail gun is now a roster turret mount (EnemyRoster.BOMBER_TAIL_MOUNT) realized by MountBuilder
	# as an EnemyTurret child of the TurretTail marker — toggle it by type, not the bespoke "TailGun" node.
	for tg in find_children("*", "EnemyTurret", true, false):
		tg.set_process(on)
		tg.set_physics_process(on)


# Blank the engine contrails while the bomber is overhead (their top_level nodes don't follow the
# hidden body); _update_engine_trails rebuilds them when control returns.
func _clear_engine_trails() -> void:
	for line in _trails:
		if line != null and is_instance_valid(line):
			line.points = PackedVector2Array()


func _build_engine_trails() -> void:
	var parent := get_parent()
	if parent == null:
		return
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
		line.top_level = true
		line.z_index = 1
		var grad := Gradient.new()
		grad.set_color(0, TRAIL_COLOR)
		grad.set_color(1, Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, 0.0))
		line.gradient = grad
		parent.add_child(line)
		_trails.append(line)


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
		var nozzle: Vector2 = marker.global_position
		var len_px: float = PLUME_LEN * randf_range(0.78, 1.0)
		line.points = PackedVector2Array([nozzle, nozzle + Vector2(0.0, len_px)])


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
