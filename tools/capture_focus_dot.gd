extends SceneTree

# Boots main.tscn, force-toggles the focus dot on the player via direct
# method call so we can verify the dot renders at the player's center
# even without simulating an actual Shift keypress (headless can't
# inject keys reliably).

const OUT_DIR := "user://focus_dot_shot"


func _init() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(25):
		await process_frame
	if current_scene:
		var p = current_scene.find_child("Player", true, false)
		if p and p.has_method("_update_focus_dot"):
			p._update_focus_dot(true)
	for _i in range(5):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved: ", ProjectSettings.globalize_path(OUT_DIR + "/frame.png"))
	quit()
