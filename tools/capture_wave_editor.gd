extends SceneTree

const OUT_DIR := "user://wave_editor_shot"


func _init() -> void:
	change_scene_to_file("res://scenes/dev/wave_editor.tscn")
	for _i in range(15):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved: ", ProjectSettings.globalize_path(OUT_DIR + "/frame.png"))
	quit()
