extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyDroneCarrier

# Drone carrier — holds high, releases hunter drones, then retreats UP once its drone budget is
# spent. On-lane migration 2026-06-08: enter→settle→drift is now the shared Drift pattern (matrix
# assigns drift_high). The spent→leave-upward exit stays bespoke (a state-triggered exit the
# pattern vocabulary doesn't cover) — when _leaving, _process climbs out instead of drifting.
# Drone release is unchanged (drones are independent, parented to the scene root).

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
# Released swarm unit. Was enemy_hunter_drone (retired 2026-06-20); now the core Flechette —
# the Hive seeds a swarm of flechettes. FLAG: confirm this is the intended drone (vs. a corp
# small unit like enemy_c_s_sapper).
const DRONE_SCENE = preload("res://scenes/enemies/core/enemy_core_s_flechette.tscn")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const Drift = preload("res://scripts/enemies/patterns/drift.gd")

const MAX_DRONES_TOTAL := 10
const ACTIVE_TARGET    := 3
const LEAVE_SPEED      := 105.0   # upward retreat once spent (was ENTER_SPEED * 1.5)
const MountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")

# Drone-swarm config — defaults from the consts above, OVERRIDABLE by a spawner-provided ENTITY
# hardpoint (the bench/roster) so the Hive is tunable instead of fully bespoke (Roman 2026-07-04:
# "bespoke drone spawning that I can't remove/configure"). The respawn-budget loop (keep _active_target
# alive until _max_drones total, then leave) stays bespoke — no hardpoint trigger expresses it.
var _drone_scene: PackedScene = DRONE_SCENE
var _active_target: int = ACTIVE_TARGET
var _max_drones: int = MAX_DRONES_TOTAL

var _total_released: int = 0
var _active_drones: int = 0
var _leaving: bool = false


func _ready() -> void:
	max_health    = 16
	bounty_value  = 40
	auto_rotate   = false
	display_scale = 1.5
	if movement == null:
		var d := Drift.new()
		d.hover_y = 55.0
		movement = d
	# Read a spawner-provided ENTITY hardpoint (bench/roster) to configure the swarm, then strip it from
	# mounts so it doesn't ALSO auto-emit — the Hive drives spawning through its bespoke respawn loop.
	var kept: Array = []
	for m in mounts:
		if m != null and "kind" in m and int(m.kind) == MountSpecC.Kind.ENTITY:
			if m.payload_scene != null:
				_drone_scene = m.payload_scene
			if m.count > 0:
				_active_target = m.count
			if m.max_emits > 0:
				_max_drones = m.max_emits
		else:
			kept.append(m)
	mounts = kept
	super._ready()
	call_deferred("_release_initial_drones")


func _release_initial_drones() -> void:
	for i in _active_target:
		_release_drone()


func _release_drone() -> void:
	if _total_released >= _max_drones or _dying:
		return
	var d = _drone_scene.instantiate()
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	world.add_child(d)
	d.global_position = global_position + Vector2(randf_range(-20, 20), 0)
	d.movement = BeelinePlayer.new()
	# Bound the recycle (Roman 2026-07-04): a directly-released flechette keeps enemy_base's -1
	# (unlimited) recycle default, and with the default CYCLE_BOTTOM offscreen mode that loops the
	# drone back up FOREVER — the "endless flechettes that recycle at 1/4 size" seen anywhere a Hive
	# spawns (Enemy Bench / Combat Lab / faction previews) and in real combat. A couple of hunt passes
	# then a clean leave keeps the swarm lively without the infinite loop (matches chaff recycle).
	d.recycle_passes = 2
	d.start(d.global_position)
	d.connect("died", _on_drone_died)
	_total_released += 1
	_active_drones += 1
	if _total_released >= _max_drones:
		_leaving = true


func _on_drone_died(_value: int) -> void:
	_active_drones = max(0, _active_drones - 1)
	if not _leaving and _total_released < _max_drones:
		_release_drone()


func _process(delta: float) -> void:
	# Spent → climb out the top (bespoke exit; the Drift pattern only holds). Otherwise the
	# pattern drives enter→settle→hold via enemy_core.
	if _leaving and not _dying:
		global_position.y -= LEAVE_SPEED * delta
		if global_position.y < -80.0:
			queue_free()
		return
	super._process(delta)


func explode() -> void:
	# Released drones are independent — do NOT kill them when the carrier dies.
	super.explode()
