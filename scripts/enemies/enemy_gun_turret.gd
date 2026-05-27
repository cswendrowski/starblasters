extends EnemyBase
class_name EnemyGunTurret

# Gun turret — child of EnemyCruiser. Aiming and firing delegated to an
# EnemyTurret child; this script retains only health/bounty/explode.

func _ready() -> void:
	max_health    = 4
	bounty_value  = 5
	auto_rotate   = false
	display_scale = 0.5
	super._ready()
	var t := EnemyTurret.new()
	t.rotation_speed    = 1.8
	t.fire_interval_min = 2.5
	t.fire_interval_max = 2.5
	t.aim_tolerance_deg = 10.3  # 0.18 rad
	t.bullet_speed      = 160.0
	add_child(t)
