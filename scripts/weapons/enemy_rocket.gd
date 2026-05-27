extends "res://scripts/projectiles/base_bullet.gd"
class_name EnemyRocket

# Enemy rocket fired by the Gunship. Compared with generic enemy_bullet:
#   - Heads downward at higher speed
#   - Deals 2 damage on contact
#   - Can be shot down by player bullets (1 HP, is in "enemies" group)
#   - is_hazard = true so dead rockets don't gate wave-clear
#   - Explodes visually but deals NO damage when destroyed by player fire

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const MissileSmokeTrail = preload("res://scripts/effects/missile_smoke_trail.gd")

var health: int = 1
var is_hazard: bool = true  # don't gate wave-clear (director.gd checks this)


func _init() -> void:
	target_group = "player"
	velocity_dir = Vector2(0, 1)
	speed = 280.0
	damage = 2
	max_lifetime = 4.0
	impact_kind = 1  # EXPLOSIVE


func _ready() -> void:
	add_to_group("enemies")
	super._ready()
	# Attach the smoke trail with downward drift flipped (rocket travels
	# downward; without flip the trail drifts further down = in front of the
	# rocket instead of behind it).
	var trail = MissileSmokeTrail.new()
	trail.flip_drift = true
	get_tree().root.call_deferred("add_child", trail)
	trail.call_deferred("attach_to", self)


# Called by player bullets via _apply_enemy_hit → area.take_hit(damage).
# We don't need to apply incoming damage (1-shot regardless), just die.
func take_hit(_dmg: int = 1) -> void:
	if _killed:
		return
	_killed = true
	# Small silent explosion — no player damage, just visual pop.
	ExplosionFx.play(global_position, 0.5, false)
	queue_free()
