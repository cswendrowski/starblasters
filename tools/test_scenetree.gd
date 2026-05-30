extends SceneTree

func _initialize() -> void:
	print("SceneTree initialized!")
	var dir_path := ProjectSettings.globalize_path("res://captures/frames_light_patterns")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(dir_path + "/test_scenetree.txt", FileAccess.WRITE)
	if f:
		f.store_line("SceneTree test OK")
	quit()
