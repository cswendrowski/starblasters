extends "res://scripts/boss.gd"

# Sentinel — defensive turret boss. Very high HP, slow movement, fires
# 5-bullet spread on a slow cadence and periodically drops a salvo of
# drifting missiles. No minions, no black hole.

const MissileScene = preload("res://scenes/projectiles/drifting_missile.tscn")
const MISSILE_INTERVAL := 6.5
const MISSILES_PER_SALVO := 4

var _missile_t: float = 0.0


func _ready() -> void:
	max_health = 320  # ×2 balance pass 2026-05-22
	bounty_value = 400
	display_scale = 1.0
	fire_interval_min = 1.4
	fire_interval_max = 1.9
	minions_per_spawn = 0
	minion_max_alive = 0
	black_hole_interval_min = 9999.0
	black_hole_interval_max = 9999.0
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _dying:
		return
	_missile_t += delta
	if _missile_t >= MISSILE_INTERVAL:
		_missile_t = 0.0
		_drop_missile_salvo()


# Drop a salvo of homing missiles. They drift briefly, ignite, and chase the
# player — same drifting missile the Interceptor enemy drops.
func _drop_missile_salvo() -> void:
	for i in MISSILES_PER_SALVO:
		var m = MissileScene.instantiate()
		get_parent().add_child(m)
		# Spread them in a small arc below the boss.
		var t: float = 0.0
		if MISSILES_PER_SALVO > 1:
			t = (float(i) / float(MISSILES_PER_SALVO - 1)) * 2.0 - 1.0
		var spawn_pos: Vector2 = global_position + Vector2(t * 40.0, 40.0)
		if m.has_method("start"):
			m.start(spawn_pos)
		else:
			m.global_position = spawn_pos
