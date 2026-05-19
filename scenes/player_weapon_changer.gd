extends Node2D
var weapons: Array =["None"]
@export var casing_particle_scene: PackedScene
@export var flash_particle_scene: PackedScene
var current_weapon_index = 0
var current_weapon = weapons[current_weapon_index]

func appendguns():
	#var nose_machinegun = load("res://weapon_nose_gun.tscn").instantiate()
	#weapons.append(nose_machinegun)
	pass
		
func _ready():
	await appendguns()
	current_weapon = weapons[current_weapon_index]
	preload("res://scenes/effects/shell_eject_small.tscn")

func _process(_float):
	if Input.is_action_pressed("shoot_nose") and $"../../MinigunCooldown".is_stopped():
		shoot()
	if Input.is_action_just_pressed("weapon_previous"):
		var direction = -1
		switch_weapon(direction)
	if Input.is_action_just_pressed("weapon_next"):
		var direction = 1
		switch_weapon(direction)
	
func switch_weapon(direction):
	current_weapon_index += direction
	if current_weapon_index > weapons.size()-1 :
		current_weapon_index = 0
	if current_weapon_index < 0:
		current_weapon_index = weapons.size()-1
	current_weapon = weapons[current_weapon_index]

func shoot():
	var p = current_weapon.instantiate()
	var casing_spawn_point: Marker2D = $"../Gun_Nose_Eject"
	var particle_instance = casing_particle_scene.instantiate()
	particle_instance.global_position = casing_spawn_point.global_position
	get_tree().current_scene.add_child(particle_instance)
	particle_instance.emitting = true
	var flash_spawn_point: Marker2D = $"../Gun_Nose"
	var flash_instance = flash_particle_scene.instantiate()
	flash_instance.global_position = flash_spawn_point.global_position
	get_tree().current_scene.add_child(flash_instance)
	flash_instance.emitting = true
	get_tree().root.add_child(p)
	p.transform =$"../Gun_Nose".global_transform
	$"../../MinigunCooldown".start()
	$"../../ShootMinigun".pitch_scale = randf_range(0.98, 1.02)
	$"../../ShootMinigun".play()
	#var b = current_weapon.instantiate()
	#get_tree().root.add_child(b)
	#b.start(position + Vector2(0, -8))
	#var tween = create_tween().set_parallel(false)
	#tween.tween_property($"../Gun_Nose", "position:y", 1, 0.1)
	#tween.tween_property($"../Gun_Nose", "position:y", 0, 0.05)
