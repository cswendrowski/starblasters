extends SceneTree

const OUT_DIR := "user://side_pods_frames"
const DURATION := 2.5
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
	var SidePodsScript = load("res://scripts/parts/side_pods.gd")
	var BulletDefault = load("res://scenes/projectiles/bullet.tscn")
	var pods = SidePodsScript.new()
	pods.mark = 5
	pods.bullet_scene = BulletDefault
	pods.apply(player)
	Input.action_press("shoot2")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for f in range(int(DURATION * FPS)):
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%04d.png" % [OUT_DIR, f])
	Input.action_release("shoot2")
	print("saved %d frames" % int(DURATION * FPS))
	quit()
