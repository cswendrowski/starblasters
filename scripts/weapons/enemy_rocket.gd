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
const EngineFlareCls := preload("res://scripts/effects/engine_flare.gd")
const ANIM_FPS := 12.0

var health: int = 1
var is_hazard: bool = true  # don't gate wave-clear (director.gd checks this)
var _anim_frame_t := 0.0


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
	# Rotate sprite to face travel direction (downward). New asymmetric rocket
	# art has the nose at the top of the sheet; + PI*0.5 makes the sprite's
	# "up" point along the velocity vector (matching base_missile.gd convention).
	rotation = velocity_dir.angle() + PI * 0.5
	# Engine flare at the exhaust marker. Enemy rockets fire immediately
	# (no drift), so the flare is visible from spawn — no ignition gate.
	var exhaust: Node2D = get_node_or_null("exhaust_point")
	if exhaust != null:
		var flare: Sprite2D = EngineFlareCls.new()
		exhaust.add_child.call_deferred(flare)
	# Attach the smoke trail with downward drift flipped (rocket travels
	# downward; without flip the trail drifts further down = in front of the
	# rocket instead of behind it). Emit from the exhaust marker when present.
	var trail: MissileSmokeTrail = MissileSmokeTrail.new()
	trail.flip_drift = true
	get_tree().root.call_deferred("add_child", trail)
	var emitter: Node2D = exhaust if exhaust != null else self
	trail.call_deferred("attach_to", emitter)


func _process(delta: float) -> void:
	# Thruster frame loop (no-op for single-frame sheets)
	if has_node("Sprite2D"):
		var sprite: Sprite2D = $Sprite2D
		if sprite.hframes > 1:
			_anim_frame_t += delta
			sprite.frame = int(_anim_frame_t * ANIM_FPS) % sprite.hframes


# Called by player bullets via _apply_enemy_hit → area.take_hit(damage).
# We don't need to apply incoming damage (1-shot regardless), just die.
func take_hit(_dmg: int = 1) -> void:
	if _killed:
		return
	_killed = true
	# Small silent explosion — no player damage, just visual pop.
	ExplosionFx.play(global_position, 0.5, false)
	queue_free()
