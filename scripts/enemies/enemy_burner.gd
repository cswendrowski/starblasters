extends EnemyBase

# Burner — small uncommon enemy that flies straight down and drops fire mines
# in its wake. Fast, dies quickly, but the fire trail lingers.

const MOVE_SPEED    := 200.0   # pixels per second downward
const DROP_INTERVAL := 0.6     # seconds between fire-mine drops
const FireMineScene = preload("res://scenes/enemies/enemy_fire_mine.tscn")

var _drop_t: float = 0.0


func _ready() -> void:
	max_health = 2
	bounty_value = 10
	auto_rotate = false
	display_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	if _dying:
		return
	global_position.y += MOVE_SPEED * delta
	_drop_t += delta
	if _drop_t >= DROP_INTERVAL:
		_drop_t = 0.0
		_drop_fire_mine()
	super._process(delta)


func _drop_fire_mine() -> void:
	var m = FireMineScene.instantiate()
	get_tree().root.add_child(m)
	m.global_position = global_position
