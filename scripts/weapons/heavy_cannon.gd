extends Node2D
@export var cannon_speed = 150
@export var cannon_cooldown = 0.25
@export var cannon_scene : PackedScene
var cannon_on = true
var cannon_shoot = true

func _ready():
	start()

func start():
	$CannonCooldown.wait_time = cannon_cooldown
	
func _process(delta):
	if Input.is_action_pressed("shoot2"):
		cannonshoot()

func cannonshoot():
	if not cannon_shoot:
		return
	cannon_shoot = false
	$CannonCooldown.start()
	$CannonShoot.play()
	var b = cannon_scene.instantiate()
	get_tree().root.add_child(b)
	b.start(position + Vector2(0, -8))
	var tween = create_tween().set_parallel(false)
	tween.tween_property($Ship, "position:y", 1, 0.1)
	tween.tween_property($Ship, "position:y", 0, 0.05)

func _on_cannon_cooldown_timeout():
	cannon_shoot = true
