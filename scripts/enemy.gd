extends Area2D

signal died 

var start_pos = Vector2.ZERO
var speed = 0
var bullet_scene = preload("res://scenes/projectiles/enemy_bullet.tscn")
var anchor
var follow_anchor = false
var health = 1

@onready var screensize  = get_viewport_rect().size


func _ready() -> void:
	# Allow repeated $EnemyShoot.play() calls to overlap instead of cutting
	# off the previous shot (Roman feedback 2026-05-23).
	var SfxCls = load("res://scripts/effects/sfx.gd")
	if has_node("EnemyShoot"):
		SfxCls.ensure_polyphony($EnemyShoot, 4)


func play_randomized(Idle : String):
	randomize()
	$AnimationPlayer.play(Idle)
	var offset : float = randf_range(0, $AnimationPlayer.current_animation_length)
	$AnimationPlayer.advance(offset)

func start(pos):
	follow_anchor = false
	speed = 0
	position = Vector2(pos.x, -pos.y)
	start_pos = pos
	await get_tree().create_timer(randf_range(0.25, 0.55)).timeout
	var tw = create_tween().set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "position:y", start_pos.y, 1.4)
	await tw.finished
	follow_anchor = true
	#play_randomized("bounce")
	$MoveTimer.wait_time = randf_range(5, 20)
	$MoveTimer.start()
	$ShootTimer.wait_time = randf_range(4, 20)
	$ShootTimer.start()
	
func _process(delta):
	if follow_anchor:
		position = start_pos + anchor.position
	position.y += speed * delta
	if position.y > screensize.y + 32:
		start(start_pos)

func hit():
	$ParticleHit.restart()

func explode():
	speed = 0
	$AnimationPlayer.play("explode")
	$ParticleExplode.restart()
	$ParticleHullBits.restart()
	set_deferred("monitorable", false)
	died.emit(5)
	# Detach the death SFX so it survives queue_free() below and plays
	# to completion (Roman feedback 2026-05-23).
	var SfxCls = load("res://scripts/effects/sfx.gd")
	SfxCls.play_node_detached($EnemyDie)
	await $AnimationPlayer.animation_finished
	queue_free()

func _on_timer_timeout():
	speed = randf_range(75, 100)
	follow_anchor = false

func _on_shoot_timer_timeout():
	var b = bullet_scene.instantiate()
	get_tree().root.add_child(b)
	b.start(position)
	$ShootTimer.wait_time = randf_range(4, 20)
	$ShootTimer.start()
	$EnemyShoot.play()
