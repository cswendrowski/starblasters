extends SceneTree

const OUT_DIR := "user://outpost_shot"


func _init() -> void:
	# Seed Run with some bounty so the buttons aren't all dimmed-out.
	if root.has_node("Run"):
		var run = root.get_node("Run")
		if run.has_method("new_run"):
			run.new_run()
		run.bounty = 200
		run.max_hull = 50
		run.current_hull = 30
		run.ammo = 500
		run.max_super_charges = 3
		run.super_charges = 1
	change_scene_to_file("res://scenes/outpost.tscn")
	for _i in range(30):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved")
	quit()
