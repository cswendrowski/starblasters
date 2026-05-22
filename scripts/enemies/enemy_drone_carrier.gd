extends EnemyBase
class_name EnemyDroneCarrier

const DRONE_SCENE = preload("res://scenes/enemies/enemy_hunter_drone.tscn")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")

const MAX_DRONES_TOTAL := 10
const ACTIVE_TARGET    := 3
const SETTLE_Y         := 55.0
const ENTER_SPEED      := 70.0
const DRIFT_RANGE      := 50.0
const DRIFT_FREQ       := 0.15

var _settled: bool = false
var _drift_t: float = 0.0
var _drift_origin: float = 0.0
var _total_released: int = 0
var _active_drones: int = 0
var _leaving: bool = false


func _ready() -> void:
	max_health    = 16
	bounty_value  = 40
	auto_rotate   = false
	display_scale = 1.5
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
	# Hunter drone extends enemy_core — assign a beeline movement pattern and
	# call start() so it actually chases the player. Without this the drone
	# instantiates with no pattern and sits still (Roman/advisor 2026-05-22).
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
	if _dying:
		return
	_drift_t += delta
	if not _settled:
		global_position.y += ENTER_SPEED * delta
		if global_position.y >= SETTLE_Y:
			global_position.y = SETTLE_Y
			_settled = true
			_drift_origin = global_position.x
	elif _leaving:
		global_position.y -= ENTER_SPEED * 1.5 * delta
		if global_position.y < -80:
			queue_free()
	else:
		global_position.x = _drift_origin + sin(_drift_t * DRIFT_FREQ * TAU) * DRIFT_RANGE
	super._process(delta)


func explode() -> void:
	# Drones already released into the scene root are independent — do NOT
	# kill them when the carrier dies. The player still has to deal with them.
	super.explode()
