extends SceneTree

# Boot main.tscn, set a plausible bounty value, screenshot. The HD bounty
# label should appear top-right in the right gutter, rasterised at 2×
# density (font_size=20 in 960×540 SubViewport).

const OUT_DIR := "user://hd_bounty"


func _init() -> void:
	# Seed bounty before the scene loads so update_bounty paints the label
	# at first show.
	if root.has_node("Run"):
		var run = root.get_node("Run")
		if "bounty" in run:
			run.bounty = 1247
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(30):
		await process_frame
	# Defensive: if update_bounty signal didn't fire, set explicitly.
	if current_scene:
		var ui = current_scene.find_child("UI", true, false)
		if ui and ui.has_method("update_bounty"):
			ui.update_bounty(1247)
		# Force wave label visible for the comparison.
		var wl = current_scene.find_child("WaveLabel", true, false)
		if wl:
			wl.visible = true
			wl.modulate = Color(1, 1, 1, 1)
			if wl is Label:
				wl.text = "WAVE 3 / 7"
	for _i in range(8):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved: ", ProjectSettings.globalize_path(OUT_DIR + "/frame.png"))
	quit()
