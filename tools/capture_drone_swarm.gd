extends SceneTree

const OUT_DIR := "user://drone_swarm_frames"
const DURATION := 4.0
const FPS := 30


func _init() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(120):
		await process_frame
	if current_scene == null:
		quit()
		return
	var player = current_scene.find_child("Player", true, false)
	if player == null:
		quit()
		return
	# Equip the Drone Swarm super, then trigger it.
	var DroneSwarmScript = load("res://scripts/parts/drone_swarm.gd")
	var swarm = DroneSwarmScript.new()
	swarm.mark = 3
	swarm.apply(player)
	# Activate the super weapon now so drones spawn for the duration.
	swarm.activate(player)
	# Hold primary so the swarm has something to piggyback.
	Input.action_press("shoot")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for f in range(int(DURATION * FPS)):
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%04d.png" % [OUT_DIR, f])
	Input.action_release("shoot")
	print("saved %d frames" % int(DURATION * FPS))
	quit()
