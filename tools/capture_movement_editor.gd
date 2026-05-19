extends SceneTree

const OUT_DIR := "user://movement_editor_shot"


func _init() -> void:
	change_scene_to_file("res://scenes/dev/movement_pattern_editor.tscn")
	# Wait several frames so the live preview tick can move the dummy.
	for _i in range(60):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved: ", ProjectSettings.globalize_path(OUT_DIR + "/frame.png"))
	quit()
