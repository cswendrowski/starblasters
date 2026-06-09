extends "res://scripts/enemy_core.gd"
class_name EnemyDroneCarrier

# Drone carrier — holds high, releases hunter drones, then retreats UP once its drone budget is
# spent. On-lane migration 2026-06-08: enter→settle→drift is now the shared Drift pattern (matrix
# assigns drift_high). The spent→leave-upward exit stays bespoke (a state-triggered exit the
# pattern vocabulary doesn't cover) — when _leaving, _process climbs out instead of drifting.
# Drone release is unchanged (drones are independent, parented to the scene root).

const DRONE_SCENE = preload("res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const Drift = preload("res://scripts/enemies/patterns/drift.gd")

const MAX_DRONES_TOTAL := 10
const ACTIVE_TARGET    := 3
const LEAVE_SPEED      := 105.0   # upward retreat once spent (was ENTER_SPEED * 1.5)

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
	super._ready()
	call_deferred("_release_initial_drones")


func _release_initial_drones() -> void:
	for i in ACTIVE_TARGET:
		_release_drone()


func _release_drone() -> void:
	if _total_released >= MAX_DRONES_TOTAL or _dying:
		return
	var d = DRONE_SCENE.instantiate()
	get_tree().root.add_child(d)
	d.global_position = global_position + Vector2(randf_range(-20, 20), 0)
	d.movement = BeelinePlayer.new()
	d.start(d.global_position)
	d.connect("died", _on_drone_died)
	_total_released += 1
	_active_drones += 1
	if _total_released >= MAX_DRONES_TOTAL:
		_leaving = true


func _on_drone_died(_value: int) -> void:
	_active_drones = max(0, _active_drones - 1)
	if not _leaving and _total_released < MAX_DRONES_TOTAL:
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
