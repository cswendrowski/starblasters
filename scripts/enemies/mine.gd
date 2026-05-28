extends "res://scripts/enemies/enemy_base.gd"

# Basic mine (Roman, 2026-05-18 mine pass: "Use mine_basic, it's a basic
# mine that explodes on contact with the player. This is the most common
# mine type, no frills, no special features"). Drifts straight down,
# explodes on player contact. Bullet hits damage it normally; no chase
# behavior — that's the Smart Mine's job now.

@export var drift_speed: float = 90.0  # +15% per Roman 2026-05-27 (was 78.0)
@export var damage_on_collide: int = 2

var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	max_health = 2
	is_hazard = true
	bounty_value = 1
	display_scale = 1.0
	auto_rotate = false  # mines don't have a "forward"
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	position = pos
	_velocity = Vector2(0.0, drift_speed)


func _process(delta: float) -> void:
	if _dying:
		return
	position += _velocity * delta
	# Despawn off the bottom.
	if position.y > screensize.y + 32.0:
		queue_free()


func hit() -> void:
	# Standard bullet hit — flash, no behavior change. EnemyBase.take_hit
	# already routes lethal hits through explode().
	if has_node("ParticleHit"):
		$ParticleHit.restart()


# Mine-specific death VFX — larger explosion + sfx + burn — overrides the
# default EnemyBase.explode.
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
