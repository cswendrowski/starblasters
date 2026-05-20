extends SceneTree

# Boot asteroid_field hazard, capture 90 frames for a GIF showing the
# new 1px black outlines on the playspace asteroids.

const OUT_DIR := "user://asteroid_outline_frames"
const DURATION := 3.0
const FPS := 30


func _init() -> void:
	if root.has_node("Run"):
		var run = root.get_node("Run")
		if run.has_method("new_run"):
			run.new_run()
		run.test_mode_active = true
		run.current_hazard_subtype = "asteroid_field"
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
	change_scene_to_file("res://scenes/main.tscn")
	# Let the intro slide-in finish so asteroids actually spawn.
	for _i in range(120):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for f in range(int(DURATION * FPS)):
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%04d.png" % [OUT_DIR, f])
	print("saved %d frames to %s" % [int(DURATION * FPS), ProjectSettings.globalize_path(OUT_DIR)])
	quit()
