extends EnemyBase
class_name EnemyCruiser

# Large cruiser with three child turrets: one beam turret (center) and
# two gun turrets (flanks). Turrets are children — they follow the cruiser
# automatically and are freed when the cruiser is freed.
#
# NOTE: display_scale = 2.0 affects VFX blast count and debris only.
# The sprite visual size is determined by the collision/sprite in the .tscn.

const ENTER_SPEED   := 80.0
const SETTLE_Y      := 48.0
const DRIFT_RANGE   := 40.0
const DRIFT_HZ      := 0.15  # cycles per second

var _settled: bool = false
var _drift_origin: float = 0.0
var _drift_t: float = 0.0

var _beam_turret: Node = null
var _gun_turret_l: Node = null
var _gun_turret_r: Node = null


func _ready() -> void:
	max_health   = 16
	bounty_value = 40
	auto_rotate  = false
	display_scale = 2.0
	super._ready()
	call_deferred("_spawn_turrets")


func _spawn_turrets() -> void:
	var BeamScene = load("res://scenes/enemies/enemy_beam_turret.tscn")
	var GunScene  = load("res://scenes/enemies/enemy_gun_turret.tscn")
	if BeamScene == null or GunScene == null:
		push_error("EnemyCruiser: failed to load turret scenes")
		return
	_beam_turret  = BeamScene.instantiate()
	_gun_turret_l = GunScene.instantiate()
	_gun_turret_r = GunScene.instantiate()
	_beam_turret.position  = Vector2(0, -10)
	_gun_turret_l.position = Vector2(-20, 4)
	_gun_turret_r.position = Vector2(20, 4)
	add_child(_beam_turret)
	add_child(_gun_turret_l)
	add_child(_gun_turret_r)


func _process(delta: float) -> void:
	_move(delta)
	super._process(delta)


func _move(delta: float) -> void:
	if _dying:
		return
	_drift_t += delta
	if not _settled:
		if global_position.y < SETTLE_Y:
			global_position.y += ENTER_SPEED * delta
		else:
			global_position.y = SETTLE_Y
			_settled = true
			_drift_origin = global_position.x
	else:
		# Slow left-right drift: sin oscillation at DRIFT_HZ cycles/sec
		var drift_x := sin(_drift_t * DRIFT_HZ * TAU) * DRIFT_RANGE
		global_position.x = _drift_origin + drift_x


func explode() -> void:
	# Kill surviving turrets before the parent explodes so their died signals
	# fire and their bounties are counted. Turrets would otherwise be freed
	# with the parent mid-await in their own explode().
	for t in [_beam_turret, _gun_turret_l, _gun_turret_r]:
		if t and is_instance_valid(t) and t.has_method("explode"):
			if not ("_dying" in t and t._dying):
				t.explode()
	super.explode()
